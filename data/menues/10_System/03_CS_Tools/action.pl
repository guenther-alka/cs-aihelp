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

    # ------------------------------------------------------------------- list
    my $rows = "<b>CS tool</b>\t<b>Current</b>\t<b>Newest</b>\t<b>Action</b>\n";
    for my $e (@{cstools_registry()}) {
        my ($present, $ver) = cstools_installed($e->{key});
        my $cur = $present ? ai_esc($ver) : "<span style='color:#a00'>not installed</span>";
        my ($new_tag, $new_assets) = cstools_release($e->{repo});
        my $new = $new_tag ? ai_esc($new_tag) : '<i>? (GitHub not reachable)</i>';
        my $action = "<form method='post' action='/cgi-bin/admin.pl' style='display:inline'>"
            . "<input type='hidden' name='member' value=\"" . ai_esc($in{'member'}) . "\">"
            . "<input type='hidden' name='id' value=\"" . ai_esc($in{'id'}) . "\">"
            . "<input type='hidden' name='l1' value=\"" . ai_esc($in{'l1'}) . "\">"
            . "<input type='hidden' name='l2' value=\"" . ai_esc($in{'l2'}) . "\">"
            . "<input type='hidden' name='l3' value=\"" . ai_esc($in{'l3'}) . "\">"
            . "<input type='hidden' name='action' value=\"" . ai_esc($in{'action'}) . "\">"
            . "<input type='hidden' name='download' value=\"" . ai_esc($e->{key}) . "\">"
            . "<input type='submit' value='download/update'></form>";
        $rows .= ai_esc($e->{name}) . "<br><span style='color:#888;font-size:11px'>" . ai_esc($e->{desc}) . "</span>\t$cur\t$new\t$action\n";
    }
    print &list2table($rows, "260px,120px,120px,160px", "", "", "n");
    print "<br><span style='color:#888;font-size:11px'>"
        . "Only the binary for the frontend OS is downloaded. The OS structure "
        . "(data/cs_server/tools/&lt;tool&gt;/&lt;platform&gt;.&lt;arch&gt;/) is kept, so csweb-gui/data can be copied to another OS "
        . "-- there the matching binary is resolved and can be fetched here if missing.</span><br>\n";

    &log_end;
} #/ my_action

1;
