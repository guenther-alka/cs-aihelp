#!
use strict;

################
# CS Tools -- download / update the cs-* daemon binaries from GitHub
# (c) napp-it.org 2026
#
# cs-aihelp / cs-sleeper are NOT bundled in napp-it cs. Their binaries are
# downloaded from the GitHub release and installed KEEPING the OS structure:
#   data/cs_server/tools/<tool>/<platform>.<arch>/<tool>[.exe]
# so that csweb-gui/data can be copied to another OS (on that OS the matching
# binary is resolved per platform; "download/update" fetches it if missing).
# The service/job settings menus just show "please download CS tools first".

sub my_action {

    my ($out, $var);
    eval { &mylib_menue_system };
    &load_lib('aihelplib.pl');      # ai_esc/ai_trim + cstoolslib (registry/download)

    my $member = $in{'member'};
    my $base   = "/cgi-bin/admin.pl?id=$in{'id'}&member=$in{'member'}&l1=$in{'l1'}&l2=$in{'l2'}&l3=$in{'l3'}";
    print "<script language='javascript'>\$('#hl').html('CS Tools -- $member')</script>\n";

    # --------------------------------------------------------- download action
    if (($in{'download'} // '') ne '') {
        my $tool = $in{'download'};
        $tool =~ s/[^a-z0-9_]//g;
        my ($ok, $msg) = cstools_download($tool, 1);
        print ($ok
            ? "<div style='color:#060;background:#dfd;border:1px solid #6a6;border-radius:4px;padding:6px 10px;display:inline-block'>"
            : "<div style='color:#a00;background:#fee;border:1px solid #faa;border-radius:4px;padding:6px 10px;display:inline-block'>")
            . ai_esc($msg) . "</div><br><br>\n";
        if ($ok && $tool eq 'aihelp') {
            my $w  = (defined $wpath && $wpath ne '') ? $wpath : '/opt/csweb-gui';
            my $bin = ai_daemon_bin();
            if (-f $bin) {
                my $out = `"$bin" start --config "$w/_cfg/cs-aihelp" 2>&1`;
                $out = ai_trim($out // '');
                print "<span style='color:#888;font-size:11px'>" . ai_esc($out) . "</span><br><br>\n" if $out ne '';
            }
        }
        print "<script>setTimeout(function(){ window.location.href=\"$base\"; }, 2500);</script>\n";
        &log_end;
        return;
    }

    # ------------------------------------------------- daemon start/stop action
    if (($in{'daemon'} // '') =~ /^(start|stop)$/) {
        my $w   = (defined $wpath && $wpath ne '') ? $wpath : '/opt/csweb-gui';
        my $bin = ai_daemon_bin();
        my $out = (-f $bin)
            ? `"$bin" $1 --config "$w/_cfg/cs-aihelp" 2>&1`
            : 'daemon not installed -- please download CS tools first';
        $out = ai_trim($out // '');
        print "<div style='color:#060;background:#dfd;border:1px solid #6a6;border-radius:4px;padding:6px 10px;display:inline-block'>"
            . ai_esc($out) . "</div><br><br>\n";
        print "<script>setTimeout(function(){ window.location.href=\"$base\"; }, 1500);</script>\n";
        &log_end;
        return;
    }

    my $dl_form = sub {
        my ($tool, $label) = @_;
        return "<form method='post' action='/cgi-bin/admin.pl' style='display:inline'>"
            . "<input type='hidden' name='member' value=\"" . ai_esc($in{'member'}) . "\">"
            . "<input type='hidden' name='id' value=\"" . ai_esc($in{'id'}) . "\">"
            . "<input type='hidden' name='l1' value=\"" . ai_esc($in{'l1'}) . "\">"
            . "<input type='hidden' name='l2' value=\"" . ai_esc($in{'l2'}) . "\">"
            . "<input type='hidden' name='l3' value=\"" . ai_esc($in{'l3'}) . "\">"
            . "<input type='hidden' name='action' value=\"" . ai_esc($in{'action'}) . "\">"
            . "<input type='hidden' name='download' value=\"" . ai_esc($tool) . "\">"
            . "<input type='submit' value=\"" . ai_esc($label) . "\"></form>";
    };
    my $daemon_form = sub {
        my ($cmd, $label) = @_;
        return "<form method='post' action='/cgi-bin/admin.pl' style='display:inline'>"
            . "<input type='hidden' name='member' value=\"" . ai_esc($in{'member'}) . "\">"
            . "<input type='hidden' name='id' value=\"" . ai_esc($in{'id'}) . "\">"
            . "<input type='hidden' name='l1' value=\"" . ai_esc($in{'l1'}) . "\">"
            . "<input type='hidden' name='l2' value=\"" . ai_esc($in{'l2'}) . "\">"
            . "<input type='hidden' name='l3' value=\"" . ai_esc($in{'l3'}) . "\">"
            . "<input type='hidden' name='action' value=\"" . ai_esc($in{'action'}) . "\">"
            . "<input type='hidden' name='daemon' value=\"" . ai_esc($cmd) . "\">"
            . "<input type='submit' value=\"" . ai_esc($label) . "\"></form>";
    };

    # ---- table 1: all CS tools (100% width) ----
    my $rows = "<tr style='background:#eee'><th style='text-align:left;padding:4px 8px'>CS tool</th>"
        . "<th style='text-align:left;padding:4px 8px'>Current</th>"
        . "<th style='text-align:left;padding:4px 8px'>Newest</th>"
        . "<th style='text-align:left;padding:4px 8px'>Action</th></tr>\n";
    for my $e (@{cstools_registry()}) {
        my ($present, $ver) = cstools_installed($e->{key});
        my $cur = $present ? ai_esc($ver) : "<span style='color:#a00'>not installed</span>";
        my $new = ai_esc(cstools_latest_tag($e->{repo}));
        $new = '<i>? (GitHub)</i>' if $new eq '';
        $rows .= "<tr><td style='padding:4px 8px'>" . ai_esc($e->{name})
            . "<br><span style='color:#888;font-size:11px'>" . ai_esc($e->{desc}) . "</span></td>"
            . "<td style='padding:4px 8px'>$cur</td>"
            . "<td style='padding:4px 8px'>$new</td>"
            . "<td style='padding:4px 8px'>" . $dl_form->($e->{key}, 'download/update') . "</td></tr>\n";
    }
    print "<b>CS tools (GitHub download/update)</b><br>\n";
    print "<table width='100%' style='border-collapse:collapse;border:1px solid #ccc'>$rows</table><br>\n";

    # ---- table 2: AI Helpdesk local management ----
    my ($ai_present, $ai_ver) = cstools_installed('aihelp');
    my $ai_run = 0;
    if ($ai_present) {
        my $w = (defined $wpath && $wpath ne '') ? $wpath : '/opt/csweb-gui';
        my $listen = '127.0.0.1:45555';
        if (open(my $fh, '<', "$w/_cfg/cs-aihelp")) {
            while (my $l = <$fh>) { if ($l =~ /^listen\s*=\s*(\S+)/) { $listen = $1; last; } }
            close $fh;
        }
        require IO::Socket::INET;
        my $sock = IO::Socket::INET->new(PeerAddr => $listen, Timeout => 1);
        if ($sock) { close $sock; $ai_run = 1; }
    }
    my $settings_link = "/cgi-bin/admin.pl?id=" . ai_esc($in{'id'}) . "&amp;member=" . ai_esc($member || '')
        . "&amp;l1=10&amp;l2=05&amp;l3=12";
    my $ai_status = $ai_present
        ? ai_esc($ai_ver) . ' &nbsp; <b>' . ($ai_run
            ? "<span style='color:darkgreen'>running</span>"
            : "<span style='color:#b26a00'>stopped</span>") . '</b>'
        : "<span style='color:#a00'>not installed</span>";
    my $ai_actions = "<a href=\"$settings_link\"><b>Settings</b></a> &nbsp; "
        . ($ai_run ? $daemon_form->('stop', 'Stop') : $daemon_form->('start', 'Start')) . ' &nbsp; '
        . $dl_form->('aihelp', 'Update');
    my $ai_rows = "<tr style='background:#eee'><th style='text-align:left;padding:4px 8px'>AI Helpdesk</th>"
        . "<th style='text-align:left;padding:4px 8px'>Status</th>"
        . "<th style='text-align:left;padding:4px 8px'>Actions</th></tr>\n"
        . "<tr><td style='padding:4px 8px'>cs-aihelp daemon<br><span style='color:#888;font-size:11px'>Setup, status, start/stop and update of the local daemon.</span></td>"
        . "<td style='padding:4px 8px'>$ai_status</td>"
        . "<td style='padding:4px 8px'>$ai_actions</td></tr>\n";
    print "<b>AI Helpdesk (local)</b><br>\n";
    print "<table width='100%' style='border-collapse:collapse;border:1px solid #ccc'>$ai_rows</table><br>\n";

    print "<span style='color:#888;font-size:11px'>"
        . "Only the binary for the frontend OS is downloaded. The OS structure "
        . "(data/cs_server/tools/&lt;tool&gt;/&lt;platform&gt;.&lt;arch&gt;/) is kept, so csweb-gui/data can be copied to another OS "
        . "-- there the matching binary is resolved and can be fetched here if missing. "
        . "Newest versions are cached for 1 h (_cfg/cstools_versions).</span><br>\n";

    &log_end;
} #/ my_action

1;
