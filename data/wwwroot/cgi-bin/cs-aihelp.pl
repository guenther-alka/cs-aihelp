#!/opt/perl/bin/perl.exe
# =============================================================================
# cs-aihelp.pl  --  AI Helpdesk JSON CGI for csweb-gui
#
# Called directly by browser JS via POST JSON.
# Auth: session (id=user,REF,token) via socketlib check_session -- the same
#       check as modifier.pl / get_async.pl.
#
# Request JSON:  { id, member, l1, l2, l3, question }
#   id         = session id "user,ref,token"
#   member     = selected backend member "hostname~ip"
#   l1/l2/l3   = current menu path (context-sensitive help)
#   question   = the user's question
#
# Response JSON: { ok, answer, sources, mode }  or  { ok:0, error }
#   answer is HTML-escaped on the server (XSS guard, see security model in
#   data/howto.ai/ai-helpdesk.info).
#
# Stufe 1 (read-only diagnostics): when tool_use=yes in _cfg/cs-aihelp, the
# CGI collects a small read-only live state (hostname, zpool list) via the
# existing socketlib &socket() channel and hands it to ai_ask() as DATA.
# Nothing is ever executed on a member -- only status/read commands.
# =============================================================================

use strict; use warnings;
use JSON::PP qw(decode_json encode_json);
use Fcntl qw(:flock);
use vars qw($tf $wpath $tpath $dpath %cfg %in %current %sys %zfs %disk $t $debug);

# bundle path (same as admin.pl) -- required under Apache; webserver.pl adds
# it to @INC globally, but the standalone CGI must be self-sufficient too
use lib "/opt/csweb-gui/data/cs_server/CGI";

my $ver = "26.08.24_12:00";

# -- Changelog
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

# ---- action: load a conversation (resume) ------------------------------
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

# ---- chat history context (resume) -------------------------------------
my $conv_id = ai_trim($in{conv} // '');
$conv_id =~ s/[^A-Za-z0-9_.-]//g;
my $conv   = $conv_id ne '' ? ai_history_load($conv_id) : undef;
my $hist_turns = 10;
my $ht = ai_trim($aicfg{history_turns} // '');
$hist_turns = $ht if $ht =~ /^\d+$/ && $ht > 0;

my @hist_msgs;
if ($conv && ref $conv->{messages} eq 'ARRAY') {
    my @all = map { { role => $_->{role}, content => $_->{text} } } @{$conv->{messages}};
    if (@all > $hist_turns) { splice(@all, 0, @all - $hist_turns); }
    # merge consecutive user turns (Anthropic wants strict user/assistant alternation)
    for my $m (@all) {
        if (@hist_msgs && $hist_msgs[-1]{role} eq 'user' && $m->{role} eq 'user') {
            $hist_msgs[-1]{content} .= "\n" . $m->{content};
        } else {
            push @hist_msgs, $m;
        }
    }
}

my $provider_use = ($in{provider_use} // 'plan') eq 'act' ? 'act' : 'plan';
my $r = ai_ask($question, $context, $live_state, \@hist_msgs, $in{tool_results}, $provider_use);

my %resp;
if (defined $r->{error}) {
    %resp = ( ok => 0, error => $r->{error} );
} else {
    # XSS guard: HTML-escape the model answer before it reaches innerHTML
    my $answer = ai_esc($r->{answer} // '');

    # persist the conversation (create new one if none)
    if ($aicfg{history} ne 'off') {
        unless ($conv) {
            $conv = { created => time(), member => $member,
                      title => substr($question, 0, 60), messages => [] };
            $conv_id = ai_new_conv_id() unless $conv_id ne '';
        }
        push @{$conv->{messages}}, { role => 'user',     ts => time(), text => $question } if $question =~ /\S/;
        push @{$conv->{messages}}, { role => 'assistant', ts => time(), text => $r->{answer} };
        $conv->{updated} = time();
        ai_history_save($conv_id, $conv) if $conv_id ne '';
        ai_history_cleanup(ai_trim($aicfg{history} // 'month'));
    }

    %resp = ( ok => 1, answer => $answer, sources => $r->{sources} // [],
              mode => $r->{mode} // '', conv => $conv_id,
              via => $r->{via} // '', action => $r->{action} // undef,
              provider_use => $r->{provider_use} // 'plan' );
}
ai_log(sprintf("qlen=%d ok=%d member=%s conv=%s",
    length($question), $resp{ok}, $member, $conv_id));

print "Content-Type: application/json\r\n\r\n" . encode_json(\%resp) . "\n";
exit;
