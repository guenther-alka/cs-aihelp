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

my $question = $in{question} // '';
my $has_tool = $in{tool_results} && ref $in{tool_results} eq 'ARRAY' && @{$in{tool_results}};
if ($question =~ /^\s*$/ && !$has_tool) {
    print "Content-Type: application/json\r\n\r\n"
        . encode_json({ ok => 0, error => 'no question' }) . "\n";
    exit;
}

# ---- Stufe 1: optional read-only live state ----------------------------
my %aicfg = ai_cfg_read();
my $live_state = '';
if ((ai_trim($aicfg{tool_use} // 'no')) eq 'yes') {
    my $ip = $current{member_ip} // '127.0.0.1';
    my @parts;
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
    $live_state = join("\n", @parts);
    $live_state = substr($live_state, 0, 4000) if length($live_state) > 4000;
}

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
