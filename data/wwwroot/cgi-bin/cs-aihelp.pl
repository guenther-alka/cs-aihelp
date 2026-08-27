#!/opt/perl/bin/perl.exe
# =============================================================================
# cs-aihelp.pl  --  AI Helpdesk session-gated PROXY to the Go daemon
#
# P2: the browser JS talks to this CGI (session check), which forwards the
# question to the Go daemon (/ask) over loopback. The daemon does RAG,
# provider call (Ollama/OpenAI), token streaming (SSE) and history. The
# exec channel stays in cs-aihelp-exec.pl (session-gated Perl).
#
# Called directly by browser JS via POST JSON.
# Auth: session (id=user,REF,token) via socketlib check_session -- the same
#       check as modifier.pl / get_async.pl.
#
# Request JSON:  { id, member, l1, l2, l3, question, conv, provider_use,
#                  tool_results, stream }
# Response:  buffered  -> JSON { ok, answer, sources, mode, conv, via,
#                               action, provider_use }
#            stream    -> SSE: data:{"t":"<token>"} ... event:done
# Stufe 1 (read-only diagnostics): when tool_use=yes in _cfg/cs-aihelp, the
# CGI collects a small read-only live state (hostname, zpool list) via the
# existing socketlib &socket() channel and hands it to the daemon as DATA.
# Nothing is ever executed on a member -- only status/read commands.
# =============================================================================

use strict; use warnings;
use JSON::PP qw(decode_json encode_json);
use Fcntl qw(:flock);
use vars qw($tf $wpath $tpath $dpath %cfg %in %current %sys %zfs %disk $t $debug);

# bundle path (same as admin.pl) -- required under Apache; webserver.pl adds
# it to @INC globally, but the standalone CGI must be self-sufficient too
use lib "/opt/csweb-gui/data/cs_server/CGI";

my $ver = "26.08.24_16:30";

# -- Changelog
# 2026.08.24_16:30  P2: session-gated proxy to the Go daemon
#   B  /ask forwarded to the Go daemon over loopback (RAG, provider, Ollama,
#      history in Go); SSE token streaming passthrough (stream:true via raw
#      socket, de-chunked); action=resume forwarded to the daemon /resume;
#      action=load stays local (shared history files).
# 2026.08.24_15:00  AI Helpdesk UI + i18n (settings/help/popup)
#   B  action=load/resume moved before the question guard (load was
#      unreachable), new action=resume returns the newest saved
#      conversation of the member for the Resume button.
# 2026.08.24_12:00  (Claude claude-sonnet-5)  AI Helpdesk MVP
#   A  initial: JSON CGI for the AI Helpdesk (cs-aihelp.pl).
#      Session check + member auth via socketlib.pl, provider call via
#      aihelplib.pl, optional read-only live_state (Stufe 1), HTML-escaped
#      answer. See data/howto.ai/ai-helpdesk.info.
#   CHANGED FILES: A data/wwwroot/cgi-bin/cs-aihelp.pl

$tf = "opt";
$wpath = "/$tf/csweb-gui";
$tpath = "$wpath/tmp";
$dpath = "$wpath/data";
mkdir $tpath unless -d $tpath;
$debug = 0;
%current = ( member_ip => '127.0.0.1' );
%sys = ();
%zfs = ();

# load socketlib.pl (session check + load_group_auth + socket)
{ my $_lib = (-f "$wpath/_my/_lib/socketlib.pl")
             ? "$wpath/_my/_lib/socketlib.pl"
             : "$dpath/menues/_lib/windows/socketlib.pl";
  require $_lib; }

# load aihelplib.pl (same _my override pattern)
{ my $_lib = (-f "$wpath/_my/_lib/aihelplib.pl")
             ? "$wpath/_my/_lib/aihelplib.pl"
             : "$dpath/menues/_lib/windows/aihelplib.pl";
  require $_lib; }

# -- log ----------------------------------------------------------------
# Minimal metadata log only. The question text is NEVER written to the log
# (privacy, secrets). Config key "log" (off|on, default on) can disable it.
my $ai_log_on = 1;
{
    my %_lc = ai_cfg_read();
    $ai_log_on = (ai_trim($_lc{log} // 'on')) ne 'off' ? 1 : 0;
}
sub ai_log {
    return unless $ai_log_on;
    my $msg = shift // '';
    my $logf = "$tpath/cs-aihelp.log";
    if (open(my $fh, '>>', $logf)) {
        my @ts = localtime();
        printf $fh "%04d.%02d.%02d.%02d.%02d  %s\n",
            $ts[5]+1900, $ts[4]+1, $ts[3], $ts[2], $ts[1], $msg;
        close $fh;
    }
}

# -- ReadParse: JSON POST body -> %in -------------------------------------
sub ReadParse {
    $| = 1;
    my $raw = '';
    my $len = $ENV{CONTENT_LENGTH} // 0;
    if ($len > 0) { read(STDIN, $raw, $len); }
    elsif (!$ENV{GATEWAY_INTERFACE}) { local $/ = undef; $raw = <STDIN> // ''; }
    return "Empty request body" unless $raw;
    eval { %in = %{ decode_json($raw) } };
    return "Invalid JSON: $@" if $@;
    return '';
}

# -- main ----------------------------------------------------------------
my $perr = ReadParse();
if ($perr) {
    print "Content-Type: application/json\r\n\r\n"
        . encode_json({ ok => 0, error => $perr }) . "\n";
    exit;
}

my $sess_err = check_session($in{id} // '');
if ($sess_err) {
    ai_log("session_error => $sess_err");
    print "Content-Type: application/json\r\n\r\n"
        . encode_json({ ok => 0, error => "Session: $sess_err" }) . "\n";
    exit;
}
# cs_26.08.26_11 (Gea: "helpdesk soll die session offen halten") -- active
# use of the AI Helpdesk (asking, resuming, switching provider) now keeps
# the underlying web-GUI session alive instead of expiring after a fixed
# 3600s of no *other* page navigation. See touch_session() in socketlib.pl
# for why this is a separate opt-in call rather than built into
# check_session() itself.
touch_session($in{id} // '');

my $member = $in{member} // 'localhost~127.0.0.1';
&load_group_auth($member);

# ---- action: load/resume a conversation (no question needed) --------------
if (($in{action} // '') eq 'load') {
    my $conv = ai_history_load($in{conv} // '');
    if (!$conv) {
        print "Content-Type: application/json\r\n\r\n"
            . encode_json({ ok => 0, error => 'conversation not found' }) . "\n";
        exit;
    }
    my @msgs = map { { role => $_->{role}, text => $_->{text} } } @{$conv->{messages} // []};
    print "Content-Type: application/json\r\n\r\n"
        . encode_json({ ok => 1, title => $conv->{title} // '', messages => \@msgs }) . "\n";
    exit;
}
if (($in{action} // '') eq 'resume') {
    # P2: forward to the Go daemon /resume (newest conversation of member)
    my $path = "/resume?member=" . uri_escape_utf8($member);
    my $resp = ai_daemon_call($path, '{}', 0);
    if ($resp eq '') {
        print "Content-Type: application/json\r\n\r\n"
            . encode_json({ ok => 0, error => 'cs-aihelp daemon not running -- start it under System > Services > AI Helpdesk' }) . "\n";
        exit;
    }
    print "Content-Type: application/json\r\n\r\n" . $resp . "\n";
    exit;
}

# ---- action: status (short-command status.pl fetch for the toolbar/
# widget buttons) ----------------------------------------------------------
# cs_26.08.27 (Gea: 6 Kurzbefehl-Buttons Pool/Disk/OS/CS/Jobs/Member, die
# server.pl's "status xxx" short command abfragen und das Ergebnis an die
# KI weiterleiten). Session-gated like every action here, but deliberately
# NOT run through ai_exec_allowed()/exec_access -- "status xxx" is a fixed,
# non-AI-composed command set (see data/howto.ai/status.info section 8),
# same trust class as the "load"/"resume" actions right above.
if (($in{action} // '') eq 'status') {
    my $class = $in{class} // '';
    unless ($class =~ /^(pool|disk|os|cs|jobs|member)$/) {
        print "Content-Type: application/json\r\n\r\n"
            . encode_json({ ok => 0, error => 'invalid status class' }) . "\n";
        exit;
    }
    my $ip = $current{member_ip} // '127.0.0.1';
    my $out = '';
    eval { $out = &socket("status $class", $ip, 60); };
    $out = "socket error: $@" if $@;
    # cs_26.08.27 (Gea, final wording: "im KI Fenster anzeigen: analyse
    # pool on $in{'member'} / &exe('status pool') aufrufen (direkt ohne
    # rueckfrage nach bestaetigung oder plan modus) / ergebnis an KI
    # geben damit die die analyse der daten vornimmt") -- $member (=
    # $in{member}, already parsed above) is the short display label; if
    # the "status $class" call itself failed (e.g. server.pl not yet
    # restarted with the new short command, or the socket call errored)
    # we short-circuit here and return an error instead of asking the
    # AI to "analyse" an error string -- that was causing the AI to
    # propose its own diagnostic command plan and ask for confirmation
    # to run it, which is exactly what this button must NOT do.
    if ($out eq '' || $out =~ /^(socket error|error::|status\.pl not found)/i) {
        print "Content-Type: application/json\r\n\r\n"
            . encode_json({ ok => 0, error => "status $class failed: $out" }) . "\n";
        exit;
    }
    my $label  = "analyse $class on $member";
    # cs_26.08.27 (Gea: "es sollten auch groessere logs oder viele platten
    # funktionieren") -- $out (esp. "disk": one full "smartctl -a" dump per
    # detected device, status.pl's disk_status(), completely unbounded; also
    # "cs": every *.log file in tmp/) can run to tens/hundreds of KB with
    # many disks or a busy log dir. Sent to the AI as-is that either blows
    # the provider's context, or -- observed live with DeepSeek's reasoning
    # model on mode2 -- silently eats the whole max_tokens budget on the
    # "thinking" phase before any visible answer, so the widget shows
    # "Sources:" and nothing else (no error; $out itself was fine). Cap what
    # goes INTO THE PROMPT at STATUS_AI_PROMPT_MAX bytes -- $out itself
    # stays full-size in the JSON "output" field / console -- cutting
    # cleanly on the last "=== ... ===" section marker (status.pl's
    # per-device/per-file separator) inside the tail so a record is never
    # sliced in half; falls back to a plain byte cut if no marker is found.
    my $STATUS_AI_PROMPT_MAX = 12000;
    my $out_for_ai = $out;
    if (length($out_for_ai) > $STATUS_AI_PROMPT_MAX) {
        my $cut = substr($out_for_ai, 0, $STATUS_AI_PROMPT_MAX);
        if ($cut =~ /\A(.*\n)===[^\n]*===\n(?:(?!\n===).)*\z/s) {
            $cut = $1;   # trim back to the end of the last COMPLETE section
        }
        my $shown = length($cut);
        my $total = length($out_for_ai);
        $out_for_ai = $cut
            . "\n[... truncated for the AI prompt: $shown of $total bytes "
            . "shown, rest omitted for length -- analyse only what is "
            . "visible above and say so ...]\n";
    }
    # cs_26.08.27 (Gea: "kann die KI die status-analyse in die eingestellte
    # Sprache uebersetzen?") -- the generic "answer in the user's language"
    # instruction in the system prompt (ai_system_prompt()/systemPrompt())
    # only works when the model can INFER a language from user-typed text;
    # this button sends a fixed, English, non-typed instruction plus mostly
    # English technical data (smartctl etc.), so there was no signal to
    # infer from and the model defaulted to English regardless of napp-it's
    # configured UI language. aihelplib.pl's ai_chat_js() now hands the
    # browser napp-it's configured language ($cfg{'select_lang'}) as
    # _aiLang, sent here as "lang" -- turn it into an explicit instruction
    # instead of leaving it to guesswork.
    my %LANG_NAME = (
        en => 'English',   de => 'German',   fr => 'French',    es => 'Spanish',
        it => 'Italian',   nl => 'Dutch',    pt => 'Portuguese', pl => 'Polish',
        ru => 'Russian',   cs => 'Czech',    cz => 'Czech',     tr => 'Turkish',
        ja => 'Japanese',  jp => 'Japanese', zh => 'Chinese',   cn => 'Chinese',
        sv => 'Swedish',   no => 'Norwegian', da => 'Danish',   fi => 'Finnish',
    );
    my $lang_code = lc(ai_trim($in{lang} // ''));
    $lang_code =~ s/[^a-z]//g;   # whitelist letters only -- drops e.g. the "!" from a stray "my!"
    $lang_code = 'en' if $lang_code eq '';
    my $lang_name = $LANG_NAME{$lang_code} || $lang_code;
    my $lang_instr = "Answer entirely in $lang_name (napp-it's configured UI language), "
        . "regardless of what language the data below happens to be in.\n\n";
    my $prompt = $lang_instr
        . "Analyse the following '$class' status data for member $member. "
        . "Answer directly using ONLY this data -- do not propose or ask to run "
        . "any further commands to gather more information.\n\n$out_for_ai";
    print "Content-Type: application/json\r\n\r\n"
        . encode_json({ ok => 1, output => $out, label => $label, prompt => $prompt }) . "\n";
    exit;
}

my $question = $in{question} // '';
my $has_tool = $in{tool_results} && ref $in{tool_results} eq 'ARRAY' && @{$in{tool_results}};
if ($question =~ /^\s*$/ && !$has_tool) {
    print "Content-Type: application/json\r\n\r\n"
        . encode_json({ ok => 0, error => 'no question' }) . "\n";
    exit;
}

# ---- live state: member identity (always) + Stufe 1 optional diagnostics --
my %aicfg = ai_cfg_read();
my $ip = $current{member_ip} // '127.0.0.1';
my @parts;

# cs_26.08.27 (Gea: "immer current{'on'} an ki mit uebergeben") -- member
# identity/version info (family;hostname;os;cs ver;zfs ver;smb) always goes
# to the AI as live-state DATA, on every question, regardless of the
# tool_use=yes/no Stufe-1 setting below. Mirrors admin.pl's own
# $current{'on'}=&socket('on',...) call (see admin.pl ~line 1068) -- but
# freshly fetched here, since this CGI is a separate process with its own
# %current, not the one admin.pl already populated for the page request.
eval {
    my $on = &socket('on', $ip, 6);
    $on =~ s/\s+$//;
    push @parts, "member on: $on" if $on =~ /\S/ && $on !~ /^error::/;
};

if ((ai_trim($aicfg{tool_use} // 'no')) eq 'yes') {
    eval {
        my $hn = &socket("hostname", $ip);
        $hn =~ s/\s+$//;
        push @parts, "hostname: $hn" if $hn =~ /\S/ && $hn !~ /^error::/;
    };
    eval {
        my $zp = &socket("zpool list", $ip);
        $zp =~ s/\s+$//;
        push @parts, "zpool list:\n$zp" if $zp =~ /\S/ && $zp !~ /^error::/;
    };
}
my $live_state = join("\n", @parts);
$live_state = substr($live_state, 0, 4000) if length($live_state) > 4000;

# ---- menu context -------------------------------------------------------
my $context = '';
if (($in{l1} // '') ne '') {
    $context = "menu: l1=" . $in{l1};
    $context .= " l2=" . $in{l2} if ($in{l2} // '') ne '';
    $context .= " l3=" . $in{l3} if ($in{l3} // '') ne '';
    $context .= " (member " . $member . ")";
}

# ---- P2: forward to the Go daemon /ask --------------------------------
my $provider_use = ($in{provider_use} // 'plan') eq 'act' ? 'act' : 'plan';
my $stream = (($in{stream} // 0) eq '1' || $in{stream} eq 'true') ? 1 : 0;
my $dbody = encode_json({
    question     => $question,
    conv         => ai_trim($in{conv} // ''),
    provider_use => $provider_use,
    context      => $context,
    live_state   => $live_state,
    tool_results => ($has_tool ? $in{tool_results} : []),
    stream       => $stream ? \1 : \0,
});

if ($stream) {
    # SSE token streaming passthrough (raw socket -> STDOUT, de-chunked)
    print "Content-Type: text/event-stream\r\n\r\n";
    my $ok = ai_daemon_call("/ask?member=" . uri_escape_utf8($member), $dbody, 1);
    if (!$ok) {
        print "data: " . encode_json({ error =>
            'cs-aihelp daemon not running -- start it under System > Services > AI Helpdesk' }) . "\n\n";
    }
    exit;
}

my $resp = ai_daemon_call("/ask?member=" . uri_escape_utf8($member), $dbody, 0);
if ($resp eq '') {
    print "Content-Type: application/json\r\n\r\n"
        . encode_json({ ok => 0, error =>
            'cs-aihelp daemon not running -- start it under System > Services > AI Helpdesk' }) . "\n";
    exit;
}
my $data;
eval { $data = decode_json($resp) };
if (!$data || ref $data ne 'HASH') {
    print "Content-Type: application/json\r\n\r\n"
        . encode_json({ ok => 0, error => 'invalid daemon response' }) . "\n";
    exit;
}
# XSS guard on the buffered answer (streaming tokens use textContent)
if ($data->{ok} && defined $data->{answer}) {
    $data->{answer} = ai_esc($data->{answer});
}
ai_log(sprintf("qlen=%d ok=%d member=%s conv=%s",
    length($question), $data->{ok} // 0, $member, $data->{conv} // ''));

print "Content-Type: application/json\r\n\r\n" . encode_json($data) . "\n";
exit;
