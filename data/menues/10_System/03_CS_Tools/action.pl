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
    print "<script language='javascript'>\$('#hl').html('CS Tools Download -- $member')</script>\n";

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
            print "<span style='color:#888;font-size:11px'>cs-aihelp downloaded -- configure/start it under System &gt; Services &gt; AI Helpdesk.</span><br><br>\n";
        }
        print "<script>setTimeout(function(){ window.location.href=\"$base\"; }, 2500);</script>\n";
        &log_end;
        return;
    }

    # ------------------------------------------------- ollama pull (background)
    if (($in{'ollama_pull'} // '') eq '1') {
        my $model = ai_trim($in{'ollama_model'} // '');
        $model =~ s/[^A-Za-z0-9:._-]//g;
        my ($ok, $msg);
        if ($model eq '') {
            ($ok, $msg) = (0, 'no model name');
        } elsif (ai_ollama_pull_bg($model)) {
            ($ok, $msg) = (1, "pulling '$model' in the background -- refresh this page later to see it in the model list");
        } else {
            ($ok, $msg) = (0, 'could not start the pull (Ollama not reachable?)');
        }
        print "<div style='color:#060;background:#dfd;border:1px solid #6a6;border-radius:4px;padding:6px 10px;display:inline-block'>"
            . ai_esc($msg) . "</div><br><br>\n";
        print "<script>setTimeout(function(){ window.location.href=\"$base\"; }, 2500);</script>\n";
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

    # ---- table 2: local AI (Ollama) download / configure ----
    # The cs-aihelp Go daemon itself is managed under System > Services >
    # AI Helpdesk (download/update of the daemon stays in table 1 above).
    my ($ollama_models, $ollama_ok) = ai_ollama_models();
    my $ollama_status = $ollama_ok
        ? "<span style='color:darkgreen'><b>running</b></span> (127.0.0.1:11434)"
        : "<span style='color:#a00'><b>not installed / not running</b></span>";
    my $ollama_models_html = $ollama_ok
        ? (@$ollama_models ? ai_esc(join(', ', @$ollama_models)) : '<i>no models pulled yet</i>')
        : '';
    my $os = lc($^O);
    my $ollama_dl;
    if ($os =~ /mswin/) {
        $ollama_dl = "<a href='https://ollama.com/download/OllamaSetup.exe' target='_blank'><b>Download Ollama (Windows)</b></a>";
    } elsif ($os =~ /darwin/) {
        $ollama_dl = "<a href='https://ollama.com/download/Ollama-darwin.zip' target='_blank'><b>Download Ollama (macOS)</b></a>";
    } elsif ($os =~ /linux/) {
        $ollama_dl = "<code>curl -fsSL https://ollama.com/install.sh | sh</code>";
    } else {
        $ollama_dl = "<span style='color:#888'>Ollama runs on Linux/macOS/Windows only -- on this OS use a remote Ollama (OLLAMA_BASE) or the free (Pollinations) fallback.</span>";
    }
    my $pull_form = '';
    if ($ollama_ok) {
        $pull_form = "<form method='post' action='/cgi-bin/admin.pl' style='display:inline'>"
            . "<input type='hidden' name='member' value=\"" . ai_esc($in{'member'}) . "\">"
            . "<input type='hidden' name='id' value=\"" . ai_esc($in{'id'}) . "\">"
            . "<input type='hidden' name='l1' value=\"" . ai_esc($in{'l1'}) . "\">"
            . "<input type='hidden' name='l2' value=\"" . ai_esc($in{'l2'}) . "\">"
            . "<input type='hidden' name='l3' value=\"" . ai_esc($in{'l3'}) . "\">"
            . "<input type='hidden' name='action' value=\"" . ai_esc($in{'action'}) . "\">"
            . "<input type='hidden' name='ollama_pull' value='1'>"
            . "<input type='text' name='ollama_model' value='llama3.1' style='width:180px' title='model tag, e.g. llama3.1, qwen2.5, mistral'>"
            . " <input type='submit' value='Pull model' style='padding:2px 8px'></form>";
    }
    my $settings_link = "/cgi-bin/admin.pl?id=" . ai_esc($in{'id'}) . "&amp;member=" . ai_esc($member || '')
        . "&amp;l1=10&amp;l2=05&amp;l3=12";
    my $ai_rows = "<tr style='background:#eee'><th style='text-align:left;padding:4px 8px'>Local AI</th>"
        . "<th style='text-align:left;padding:4px 8px'>Status</th>"
        . "<th style='text-align:left;padding:4px 8px'>Download / configure</th></tr>\n"
        . "<tr><td style='padding:4px 8px'>Ollama (local LLM)<br><span style='color:#888;font-size:11px'>Download/install Ollama and pull a local model for the AI Helpdesk. The cs-aihelp daemon itself is managed under System &gt; Services &gt; AI Helpdesk.</span></td>"
        . "<td style='padding:4px 8px'>$ollama_status<br><span style='color:#888;font-size:11px'>$ollama_models_html</span></td>"
        . "<td style='padding:4px 8px'>$ollama_dl<br><br>$pull_form<br><a href=\"$settings_link\"><b>AI Helpdesk settings</b></a></td></tr>\n";
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
