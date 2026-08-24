#!/opt/perl/bin/perl.exe
# =============================================================================
# cs-aihelp-exec.pl  --  Level 2: execute an AI-proposed command (confirmed)
#
# Session-gated CGI (same check as cs-aihelp.pl). The Go daemon only PROPOSES
# commands ([[ACTION]] block in /ask); execution happens here on the frontend
# via the existing encrypted &socket()/&exe() channel, after:
#   1. exec_access != ro
#   2. exec_deny  (always, wins)
#   3. exec_access=exec -> command class in exec_allow  (D2)
#   4. (UI has already confirmed every exec)
#
# Request JSON:  { id, member, cmd }
# Response JSON: { ok, output }  or  { ok:0, error }
# =============================================================================

use strict; use warnings;
use JSON::PP qw(decode_json encode_json);
use Fcntl qw(:flock);
use vars qw($tf $wpath $tpath $dpath %cfg %in %current %sys %zfs %disk $t $debug);

my $ver = "26.08.24_07:00";

$tf = "opt";
$wpath = "/$tf/csweb-gui";
$tpath = "$wpath/tmp";
$dpath = "$wpath/data";
mkdir $tpath unless -d $tpath;
$debug = 0;
%current = ( member_ip => '127.0.0.1' );

use lib "/opt/csweb-gui/data/cs_server/CGI";

{ my $_lib = (-f "$wpath/_my/_lib/socketlib.pl")
             ? "$wpath/_my/_lib/socketlib.pl"
             : "$dpath/menues/_lib/windows/socketlib.pl";
  require $_lib; }

{ my $_lib = (-f "$wpath/_my/_lib/aihelplib.pl")
             ? "$wpath/_my/_lib/aihelplib.pl"
             : "$dpath/menues/_lib/windows/aihelplib.pl";
  require $_lib; }

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

my $perr = ReadParse();
if ($perr) {
    print "Content-Type: application/json\r\n\r\n"
        . encode_json({ ok => 0, error => $perr }) . "\n";
    exit;
}

my $sess_err = check_session($in{id} // '');
if ($sess_err) {
    print "Content-Type: application/json\r\n\r\n"
        . encode_json({ ok => 0, error => "Session: $sess_err" }) . "\n";
    exit;
}

my $member = $in{member} // 'localhost~127.0.0.1';
&load_group_auth($member);

my $cmd = ai_trim($in{cmd} // '');
if ($cmd eq '') {
    print "Content-Type: application/json\r\n\r\n"
        . encode_json({ ok => 0, error => 'no command' }) . "\n";
    exit;
}

# combined server-side gate: access + deny + allow + exec_mode
my ($allow_ok, $allow_err) = ai_exec_allowed($cmd);
if (!$allow_ok) {
    ai_log("exec denied: $allow_err (cmd_len=" . length($cmd) . ")");
    print "Content-Type: application/json\r\n\r\n"
        . encode_json({ ok => 0, error => $allow_err }) . "\n";
    exit;
}

# execute on the selected member via the existing encrypted socket channel
my $ip = $current{member_ip} // '127.0.0.1';
my $out = '';
eval {
    $out = &socket($cmd, $ip, 120);
};
$out = defined $out ? $out : '';
$out = substr($out, 0, 16000) if length($out) > 16000;   # cap output size

ai_log("exec ok: cmd_len=" . length($cmd) . " out_len=" . length($out) . " member=$member");
print "Content-Type: application/json\r\n\r\n"
    . encode_json({ ok => 1, output => $out }) . "\n";
exit;
