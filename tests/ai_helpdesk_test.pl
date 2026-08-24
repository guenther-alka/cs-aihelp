# ai_helpdesk_test.pl -- functional test for aihelplib.pl (AI Helpdesk)
# Uses a separate mock HTTP server (ai_mock_server.pl) for the provider call.
use strict;
use FindBin qw($RealBin);
use vars qw($wpath $dpath $tpath %in);

# Portable paths: in the repo layout tests/ is a sibling of data/ (repo
# root stands in for a csweb-gui installation, CI on Linux); on the dev
# box the test also runs from C:\opt\testbase where data/howto.ai is
# absent, so fall back to the real csweb-gui path there.
(my $root = "$RealBin/..") =~ s{\\}{/}g;
$wpath = (-d "$root/data/howto.ai") ? $root : 'C:/opt/csweb-gui';
$dpath = "$wpath/data";
$tpath = "$wpath/tmp";
mkdir $tpath unless -d $tpath;
%in = ( id => 'test', member => 'localhost~127.0.0.1' );

my $ai_lib = (-d "$root/data/howto.ai")
    ? "$root/data/menues/_lib/windows/aihelplib.pl"
    : 'C:/opt/csweb-gui/data/menues/_lib/windows/aihelplib.pl';
require $ai_lib;

# guard: the test writes _cfg/cs-aihelp in place (ai_cfg_write). Back up the
# original so a full run always leaves the real config untouched, even if a
# mid-test assertion path would otherwise leave it dirty.
my $cfg_path = ai_cfg_path();
my $cfg_backup = undef;
if (-f $cfg_path) {
    open(my $bfh, '<', $cfg_path) or die "cannot read $cfg_path: $!";
    local $/ = undef;
    $cfg_backup = <$bfh>;
    close $bfh;
}
END {
    return unless defined $cfg_backup;
    if (open(my $fh, '>', $cfg_path)) {
        binmode $fh;
        print $fh $cfg_backup;
        close $fh;
    }
}

my $pass = 0;
my $fail = 0;
sub ok {
    my ($cond, $msg) = @_;
    if ($cond) { $pass++; print "ok   - $msg\n"; }
    else       { $fail++; print "FAIL - $msg\n"; }
}

# ---- 1. config read (auto-creates _cfg/cs-aihelp with defaults) ----
my %cfg = ai_cfg_read();
ok($cfg{mode} eq 'free', "config: default mode=free (got $cfg{mode})");
ok($cfg{history} eq 'month', "config: default history=month (got $cfg{history})");
ok($cfg{research} eq 'ddg', "config: default research=ddg (got $cfg{research})");
ok(-f ai_cfg_path(), "config file auto-created at " . ai_cfg_path());

# ---- 2. resolve free preset ----
my $r = ai_resolve(%cfg);
ok(defined $r, 'resolve: free mode resolves');
ok($r->{provider} eq 'free', "resolve: free provider='free' (got $r->{provider})");
ok($r->{endpoint} eq 'http://127.0.0.1:11434', "resolve: free endpoint (got $r->{endpoint})");
ok($r->{api_key} eq '', 'resolve: free has no api key');

# ---- 3. resolve off -> undef ----
my %cfg_off = ( %cfg, mode => 'off' );
ok(!defined ai_resolve(%cfg_off), 'resolve: off mode -> undef');

# ---- 4. resolve provider defaults ----
my %cfg_prov = ( %cfg, mode => 'provider', provider => 'ollama', endpoint => '', model => '' );
my $rp = ai_resolve(%cfg_prov);
ok($rp->{endpoint} eq 'http://127.0.0.1:11434/api/chat', "resolve: ollama default endpoint (got $rp->{endpoint})");
ok($rp->{model} eq 'llama3.1', "resolve: ollama default model (got $rp->{model})");

# ---- 5. light-RAG over data/howto.ai ----
my @docs = ai_retrieve('wie aktiviere ich SMB shares');
ok(scalar(@docs) > 0, 'RAG: returns hits for SMB question');
ok($docs[0]{file} =~ /smb|nfs/i, 'RAG: top hit is an SMB/NFS doc (got ' . ($docs[0]{file}//'') . ')') if @docs;

# ---- 6. history roundtrip ----
my $cid = ai_new_conv_id();
ok($cid =~ /^\d{8}_\d{6}_[0-9a-f]{8}$/, "history: conv id format ($cid)");
my $conv = { created => time(), member => 'localhost~127.0.0.1', title => 'Testgespraech',
             messages => [
                { role => 'user',     ts => time(), text => 'Frage 1' },
                { role => 'assistant', ts => time(), text => 'Antwort 1' },
             ] };
ok(ai_history_save($cid, $conv), 'history: save');
my $loaded = ai_history_load($cid);
ok($loaded && @{$loaded->{messages}} == 2, 'history: load (2 messages)');
my @list = ai_history_list();
ok(scalar(@list) >= 1, 'history: list contains the saved conversation');

# ---- 7. provider call against the local mock server (openai-compatible) ----
my $mock = { provider => 'openai', endpoint => 'http://127.0.0.1:19091/chat', model => 'mock', api_key => '' };
my $sys  = 'test system prompt';
my $res  = ai_provider_call($mock, $sys, [ { role => 'user', content => 'hallo' } ]);
ok(defined $res->{answer} && $res->{answer} =~ /MOCK-ANTWORT/, 'provider: mock openai call returns answer');

# ---- 8. provider error path (unreachable endpoint) ----
my $dead = { provider => 'openai', endpoint => 'http://127.0.0.1:1/chat', model => 'mock', api_key => '' };
my $err  = ai_provider_call($dead, $sys, [ { role => 'user', content => 'x' } ]);
ok(defined $err->{error}, 'provider: unreachable endpoint returns error (no crash)');

# ---- 9. ai_ask in off mode returns friendly error ----
ai_cfg_write(%cfg_off);
my $off = ai_ask('irgendwas', '', '');
ok(defined $off->{error} && $off->{error} =~ /mode=off/, 'ai_ask: off mode -> friendly error');
ai_cfg_write(%cfg);   # restore default

# ---- 10. free model selection (resolve carries free_model) ----
my %cfg_fm = ( %cfg, mode => 'free', free_model => 'llama3.1' );
my $rf = ai_resolve(%cfg_fm);
ok($rf->{free_model} eq 'llama3.1', 'resolve: free carries free_model');

# ---- 11. ai_ollama_models against the mock server (OLLAMA_BASE) ----
$ENV{OLLAMA_BASE} = 'http://127.0.0.1:19091';
my ($models, $reachable) = ai_ollama_models();
ok($reachable, 'ollama: mock /api/tags reachable');
ok(scalar(@$models) == 2 && $models->[0] =~ /^mock-llm/, 'ollama: model list from /api/tags');

# ---- 12. free tier Ollama path end-to-end via ai_ask (mock) ----
my %cfg_om = ( %cfg, mode => 'free', free_model => 'mock-llm:latest', history => 'off' );
ai_cfg_write(%cfg_om);
my $fa = ai_ask('testfrage', '', '');
ok(defined $fa->{answer} && $fa->{answer} =~ /MOCK-OLLAMA-ANTWORT/,
   'free: ollama mock returns answer via ai_ask');
delete $ENV{OLLAMA_BASE};
ai_cfg_write(%cfg);   # restore defaults

# ---- 13. config roundtrip preserves new keys ----
my %cfg_rw = ( %cfg, widget => 'on', free_model => 'x', history => 'week' );
ai_cfg_write(%cfg_rw);
my %cfg_rd = ai_cfg_read();
ok($cfg_rd{widget} eq 'on' && $cfg_rd{free_model} eq 'x' && $cfg_rd{history} eq 'week',
   'config: widget/free_model/history roundtrip');
ai_cfg_write(%cfg);

# ---- 14. KISS web research (DuckDuckGo Lite parsing via mock) ----
$ENV{DDG_BASE} = 'http://127.0.0.1:19091/lite';
my @rs = ai_research('zfs snapshot', 5);
ok(scalar(@rs) >= 2, 'research: ddg mock returns results');
if (@rs) {
    ok($rs[0]{url} eq 'https://mock.example.com/zfs-snap', "research: url decoded (got $rs[0]{url})");
    ok($rs[0]{title} =~ /ZFS Snapshots Guide/, "research: title extracted (got $rs[0]{title})");
    ok($rs[0]{snippet} =~ /zfs snapshot command/ && $rs[0]{snippet} !~ /<b>/, 'research: snippet stripped of tags');
}
delete $ENV{DDG_BASE};

# ---- 15. ai_ask with research=ddg appends result URLs to sources ----
my %cfg_res = ( %cfg, mode => 'provider', provider => 'openai',
    endpoint => 'http://127.0.0.1:19091/chat', model => 'mock',
    research => 'ddg', research_max => 5, history => 'off' );
ai_cfg_write(%cfg_res);
$ENV{DDG_BASE} = 'http://127.0.0.1:19091/lite';
my $ra = ai_ask('zfs snapshot wie geht das', '', '');
ok(defined $ra->{answer} && $ra->{answer} =~ /MOCK-ANTWORT/, 'research: ai_ask still answers');
ok(defined $ra->{sources} && grep { /mock\.example\.com/ } @{$ra->{sources}},
   'research: result URL appears in sources');
delete $ENV{DDG_BASE};
ai_cfg_write(%cfg);

# ---- 16. external search API (research=api, generic JSON mapping) ----
my @ap = ai_research_api('zfs', 5, 'http://127.0.0.1:19091/cse?q={q}', '');
ok(scalar(@ap) >= 2 && $ap[0]{url} eq 'https://cse.example.com/one',
   'research-api: google CSE shape mapped (got ' . ($ap[0]{url}//'') . ')');
ok($ap[0]{title} eq 'CSE Title One', 'research-api: title mapped');
my %cfg_api = ( %cfg, mode => 'provider', provider => 'openai',
    endpoint => 'http://127.0.0.1:19091/chat', model => 'mock',
    research => 'api', research_endpoint => 'http://127.0.0.1:19091/cse?q={q}',
    research_max => 5, history => 'off' );
ai_cfg_write(%cfg_api);
my $rb = ai_ask('zfs test', '', '');
ok(defined $rb->{answer} && $rb->{answer} =~ /MOCK-ANTWORT/, 'research-api: ai_ask answers');
ok(defined $rb->{sources} && grep { /cse\.example\.com/ } @{$rb->{sources}},
   'research-api: endpoint URL in sources');
ai_cfg_write(%cfg);

# ---- 17. setup fallback: provider fails -> free tier (OLLAMA mock) ----
my %cfg_fb = ( %cfg, mode => 'provider', provider => 'openai',
    endpoint => 'http://127.0.0.1:1/chat', model => 'mock',   # unreachable
    fallback => 'free', history => 'off' );
ai_cfg_write(%cfg_fb);
$ENV{OLLAMA_BASE} = 'http://127.0.0.1:19091';
my $ff = ai_ask('fallback test', '', '');
ok(defined $ff->{answer} && $ff->{answer} =~ /MOCK-OLLAMA-ANTWORT/,
   'fallback: provider dead -> free tier answers');
ok(($ff->{via} // '') eq 'free (Fallback)', 'fallback: marked as via free (Fallback)');
delete $ENV{OLLAMA_BASE};

# ---- 18. fallback=off keeps the provider error ----
my %cfg_nf = ( %cfg, mode => 'provider', provider => 'openai',
    endpoint => 'http://127.0.0.1:1/chat', model => 'mock',
    fallback => 'off', history => 'off' );
ai_cfg_write(%cfg_nf);
my $nf = ai_ask('no fallback test', '', '');
ok(defined $nf->{error}, 'fallback: off -> provider error is returned');
ai_cfg_write(%cfg);

# ---- 19. SSRF guard (_ai_safe_url) ----
ok(_ai_safe_url('https://api.openai.com/v1/chat/completions', 1), 'ssrf: public https allowed');
ok(_ai_safe_url('http://127.0.0.1:11434/api/chat', 1), 'ssrf: loopback allowed');
ok(_ai_safe_url('http://127.0.0.1:19091/chat', 1), 'ssrf: loopback test port allowed');
ok(!_ai_safe_url('http://192.168.2.10/chat', 1), 'ssrf: RFC1918 192.168 blocked');
ok(!_ai_safe_url('http://10.0.0.5/chat', 1), 'ssrf: RFC1918 10/8 blocked');
ok(!_ai_safe_url('http://172.20.0.3/chat', 1), 'ssrf: RFC1918 172.16/12 blocked');
ok(!_ai_safe_url('http://169.254.169.254/latest/meta-data', 1), 'ssrf: cloud metadata blocked');
ok(!_ai_safe_url('ftp://example.com/x', 1), 'ssrf: non-http scheme blocked');
ok(!_ai_safe_url('file:///etc/passwd', 1), 'ssrf: file scheme blocked');

# ---- 20. provider call rejects a private endpoint (SSRF) ----
my %cfg_ssrf = ( %cfg, mode => 'provider', provider => 'openai',
    endpoint => 'http://192.168.2.99/chat', model => 'mock', fallback => 'off', history => 'off' );
ai_cfg_write(%cfg_ssrf);
my $srf = ai_ask('ssrf test', '', '');
ok(defined $srf->{error} && $srf->{error} =~ /not allowed/i,
   'provider: private endpoint rejected (SSRF guard)');
ai_cfg_write(%cfg);

# ---- 21. config roundtrip includes log key ----
my %cfg_log = ( %cfg, log => 'off' );
ai_cfg_write(%cfg_log);
my %cfg_log2 = ai_cfg_read();
ok($cfg_log2{log} eq 'off', 'config: log key roundtrip');
ai_cfg_write(%cfg);

# ---- 22. SSRF: RFC1918 allowed only with allow_private ----
ok(_ai_safe_url('http://192.168.2.10/chat', 1, 1), 'ssrf: 192.168 allowed with allow_private');
ok(_ai_safe_url('http://10.0.0.5/chat', 1, 1), 'ssrf: 10/8 allowed with allow_private');
ok(!_ai_safe_url('http://192.168.2.10/chat', 1, 0), 'ssrf: 192.168 blocked by default');
ok(!_ai_safe_url('http://169.254.169.254/latest/meta-data', 1, 1), 'ssrf: metadata still blocked with allow_private');

# ---- 23. config roundtrip: ssrf_allow_private + rate_limit ----
my %cfg_sec = ( %cfg, ssrf_allow_private => 'yes', rate_limit => '30' );
ai_cfg_write(%cfg_sec);
my %cfg_sec2 = ai_cfg_read();
ok($cfg_sec2{ssrf_allow_private} eq 'yes' && $cfg_sec2{rate_limit} eq '30',
   'config: ssrf_allow_private/rate_limit roundtrip');
ai_cfg_write(%cfg);

# ---- 24. config roundtrip: level 2 keys + popup size ----
my %cfg_l2 = ( %cfg, exec_access => 'exec', exec_mode => 'auto', exec_allow => 'zfs,find,curl',
    exec_deny => 'zfs destroy|zpool destroy|rm -rf|dd |mkfs|format',
    widget_input_lines => '3', widget_answer_height => '350' );
ai_cfg_write(%cfg_l2);
my %cfg_l2r = ai_cfg_read();
ok($cfg_l2r{exec_access} eq 'exec' && $cfg_l2r{exec_mode} eq 'auto', 'config: exec_access/exec_mode roundtrip');
ok($cfg_l2r{exec_allow} eq 'zfs,find,curl' && $cfg_l2r{exec_deny} =~ /zpool destroy/,
   'config: exec_allow/exec_deny roundtrip');
ok($cfg_l2r{widget_input_lines} eq '3' && $cfg_l2r{widget_answer_height} eq '350',
   'config: popup size keys roundtrip');
my %cfg_as = ( %cfg, autostart => 'off' );
ai_cfg_write(%cfg_as);
my %cfg_asr = ai_cfg_read();
ok($cfg_asr{autostart} eq 'off', 'config: autostart key roundtrip');
ai_cfg_write(%cfg);

# ---- 25. exec default state: ro + empty allow = no execution ----
ai_cfg_write(%cfg);   # defaults: exec_access=ro, exec_allow=''
ok(ai_exec_validate('zfs list') =~ /read-only/, 'exec: ro blocks any command');
my %cfg_ro = ( %cfg, exec_access => 'exec' );
ai_cfg_write(%cfg_ro);
ok(ai_exec_validate('zfs list') =~ /exec_allow ist leer/, 'exec: exec + empty allow blocks all');
ok(ai_exec_hint(%cfg) eq '', 'exec hint: ro -> empty');   # %cfg = defaults (exec_access=ro)

# ---- 26. exec allow/deny (D2 classes) ----
my %cfg_exec = ( %cfg, exec_access => 'exec', exec_allow => 'zfs,find,curl',
    exec_deny => 'zfs destroy|zpool destroy|rm -rf|dd |mkfs|format' );
ai_cfg_write(%cfg_exec);
ok(ai_exec_validate('zfs snapshot tank/data@auto') eq '', 'exec: zfs snapshot allowed');
ok(ai_exec_validate('find /tank -name "*.log"') eq '', 'exec: find allowed');
ok(ai_exec_validate('curl -s http://example.com') eq '', 'exec: curl allowed');
ok(ai_exec_validate('rm -rf /tank/x') =~ /exec_deny/, 'exec: rm -rf blocked by deny');
ok(ai_exec_validate('zfs destroy tank/data@old') =~ /exec_deny/, 'exec: zfs destroy blocked by deny');
ok(ai_exec_validate('zpool destroy tank') =~ /exec_deny/, 'exec: zpool destroy blocked by deny');
ok(ai_exec_validate('reboot') =~ /exec_allow/, 'exec: class not in allow -> blocked');
ok(ai_exec_validate('zfs destroy tank') =~ /exec_deny/, 'exec: deny wins over allow');

# ---- 27. exec console mode: allow bypass, deny still applies ----
my %cfg_console = ( %cfg, exec_access => 'console', exec_allow => '' );
ai_cfg_write(%cfg_console);
ok(ai_exec_validate('ls -la /opt') eq '', 'console: arbitrary read-only command allowed');
ok(ai_exec_validate('zpool destroy tank') =~ /exec_deny/, 'console: deny still applies');
ok(ai_exec_hint(%cfg_console) =~ /\[\[ACTION\]\]/, 'exec hint: console -> ACTION block format');

# ---- 28. ai_exec_allowed: combined gate (exec_mode server-side) ----
my %cfg_exec2 = ( %cfg, exec_access => 'exec', exec_allow => 'zfs,find', exec_mode => 'confirm' );
ai_cfg_write(%cfg_exec2);
my ($aok1, $aerr1) = ai_exec_allowed('zfs snapshot tank/x@auto');
ok($aok1 && $aerr1 eq '', 'exec_allowed: confirm + allow -> allowed');
my %cfg_prop = ( %cfg, exec_access => 'exec', exec_allow => 'zfs,find', exec_mode => 'propose' );
ai_cfg_write(%cfg_prop);
my ($aok2, $aerr2) = ai_exec_allowed('zfs list');
ok(!$aok2 && $aerr2 =~ /propose/, 'exec_allowed: propose -> blocked server-side');
ai_cfg_write(%cfg);

# ---- 29. ai_parse_action: extract/clean [[ACTION]] block ----
my ($clean, $action) = ai_parse_action("Hier die Analyse.\n[[ACTION]]{\"cmd\":\"zfs snapshot tank/data\@auto\",\"reason\":\"test\"}[[/ACTION]]");
ok(defined $action && $action->{cmd} eq 'zfs snapshot tank/data@auto', 'parse_action: cmd extracted');
ok($clean eq 'Hier die Analyse.', 'parse_action: answer cleaned (got: ' . $clean . ')');
my ($c2, $a2) = ai_parse_action('einfache antwort');
ok(!defined $a2 && $c2 eq 'einfache antwort', 'parse_action: no block -> unchanged');
my ($c3, $a3) = ai_parse_action("text [[ACTION]]not json[[/ACTION]] ende");
ok(!defined $a3, 'parse_action: malformed block ignored');

# ---- 29. exec hint via ai_ask with ACTION mock ----
my %cfg_hint = ( %cfg, mode => 'provider', provider => 'openai',
    endpoint => 'http://127.0.0.1:19091/chat', model => 'mock',
    exec_access => 'exec', exec_allow => 'zfs', history => 'off' );
ai_cfg_write(%cfg_hint);
ok(ai_exec_hint(%cfg_hint) =~ /Allowed command classes: zfs/, 'exec hint: classes listed for exec');

# ---- 30. ai_boot_autostart: skip gates (v1.0.3) ----
ok(!defined ai_boot_autostart(mode => 'off'), 'boot_autostart: mode=off -> skip');
ok(!defined ai_boot_autostart(mode => 'free', autostart => 'off'), 'boot_autostart: autostart=off -> skip');
my $saved_wpath = $wpath;
$wpath = 'C:/opt/testbase/ai_boot_fake';   # no binary under data/cs_server/tools
ok(!defined ai_boot_autostart(mode => 'free', autostart => 'on'),
   'boot_autostart: binary missing -> skip');
$wpath = $saved_wpath;

ai_cfg_write(%cfg);   # restore defaults

print "\nRESULT: $pass passed, $fail failed\n";
exit($fail ? 1 : 0);
