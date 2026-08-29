#!
use strict;

################
# CS Tools -- download / update the cs-* daemon binaries from GitHub
# (c) napp-it.org 2026
#
# cs-aihelp / cs-sleeper are NOT bundled in napp-it cs. Their binaries are
# downloaded from the GitHub release and installed KEEPING the OS structure:
#   _my/tools/<tool>/<platform>.<arch>/<tool>[.exe]
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
        # cs_26.08.29: print (COND ? A : B) . X  would print ONLY the
        # conditional (perl list-operator paren rule) and silently drop
        # $msg + "</div>" -- the "empty green button" Gea reported.
        # The whole concatenation must be inside the print parens.
        print (($ok
            ? "<div style='color:#060;background:#dfd;border:1px solid #6a6;border-radius:4px;padding:6px 10px;display:inline-block'>"
            : "<div style='color:#a00;background:#fee;border:1px solid #faa;border-radius:4px;padding:6px 10px;display:inline-block'>")
            . ai_esc($msg) . "</div><br><br>\n");
        if ($ok && $tool eq 'aihelp') {
            print "<span style='color:#888;font-size:11px'>cs-aihelp downloaded -- configure/start it under System &gt; Services &gt; AI Helpdesk.</span><br><br>\n";
        }
        print "<script>setTimeout(function(){ window.location.href=\"$base\"; }, 2500);</script>\n";
        &log_end;
        return;
    }

    # ------------------------------------------------- ollama pull (background)
    # cs_26.08.25 (Gea: "clicked pull, nothing happens" -- ai_ollama_pull_bg()
    # used to be fire-and-forget with zero feedback). Now: start the pull,
    # then redirect to $base&pull_model=<model> so the status block below
    # (which reads ai_ollama_pull_status()) can show live progress and
    # auto-refresh while it runs.
    if (($in{'ollama_pull'} // '') eq '1') {
        my $model = ai_trim($in{'ollama_model'} // '');
        $model =~ s/[^A-Za-z0-9:._-]//g;
        my ($ok, $msg);
        if ($model eq '') {
            ($ok, $msg) = (0, 'no model name');
        } else {
            ($ok, $msg) = ai_ollama_pull_bg($model);
        }
        my $redir = $ok ? "$base&pull_model=" . ai_esc($model) : $base;
        print "<div style='color:#060;background:#dfd;border:1px solid #6a6;border-radius:4px;padding:6px 10px;display:inline-block'>"
            . ai_esc($msg) . "</div><br><br>\n";
        print "<script>setTimeout(function(){ window.location.href=\"$redir\"; }, 800);</script>\n";
        &log_end;
        return;
    }

    my $dl_form = sub {
        my ($tool, $label) = @_;
        # cs_26.08.29 (Gea: "clicked download, only an empty green button instead
        # of 'downloading, please wait'"). The POST is synchronous and webserver.pl
        # buffers the whole CGI response, so the browser shows NO feedback while
        # the download runs. onsubmit: disable the button and show "please wait"
        # immediately -- that state stays visible for the whole blocking nav.
        return "<form method='post' action='/cgi-bin/admin.pl' style='display:inline'"
            . " onsubmit='var b=this.querySelector(\"input[type=submit]\");b.disabled=true;b.value=\"downloading, please wait...\";return true;'>"
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
    my ($my_platform, $my_arch) = cstools_platform();
    for my $e (@{cstools_registry()}) {
        my ($present, $ver) = cstools_installed($e->{key});
        my $cur = $present ? ai_esc($ver) : "<span style='color:#a00'>not installed</span>";
        my $new = ai_esc(cstools_latest_tag($e->{repo}));
        $new = '<i>? (GitHub)</i>' if $new eq '';
        # cs_26.08.25 (Gea: "csfreeze4snap geht nicht" -- e.g. cs-freeze4snap
        # only ships a Linux asset (Windows has no fsfreeze equivalent; VSS
        # would need a separate tool). Previously the button was shown
        # regardless and only failed with a generic error after clicking.
        # Now: grey out + explain up front for tools with no asset for this
        # OS, instead of letting the user hit an avoidable error.
        my $supported = (cstools_asset_platform($e, $my_platform) ne '');
        my $action_html = $supported
            ? $dl_form->($e->{key}, 'download/update')
            : "<span style='color:#888;font-size:11px'>not available on this OS ($my_platform/$my_arch)</span>";
        $rows .= "<tr><td style='padding:4px 8px'>" . ai_esc($e->{name})
            . "<br><span style='color:#888;font-size:11px'>" . ai_esc($e->{desc}) . "</span></td>"
            . "<td style='padding:4px 8px'>$cur</td>"
            . "<td style='padding:4px 8px'>$new</td>"
            . "<td style='padding:4px 8px'>$action_html</td></tr>\n";
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
    my $ollama_base_env = ai_esc($ENV{OLLAMA_BASE} // 'http://127.0.0.1:11434 (default)');
    my $quick_models = ['qwen2.5:7b', 'mistral', 'phi4-mini', 'gemma2'];
    my $quick_vision_models = ['llama3.2-vision:3b', 'llama3.2-vision', 'llava:34b'];
    my $pull_form = '';
    if ($ollama_ok) {
        my $quick_html = '';
        for my $m (@$quick_models) {
            $quick_html .= "<a href='#' onclick=\"document.getElementById('ollama_model_fld').value='"
                . ai_esc($m) . "';return false;\" style='margin-right:6px;font-size:11px'>" . ai_esc($m) . "</a>";
        }
        # cs_26.08.28: vision-modelle als eigene quick-pick zeile
        my $quick_vision_html = '';
        for my $m (@$quick_vision_models) {
            $quick_vision_html .= "<a href='#' onclick=\"document.getElementById('ollama_model_fld').value='"
                . ai_esc($m) . "';return false;\" style='margin-right:6px;font-size:11px'>" . ai_esc($m) . "</a>";
        }
        $pull_form = "<form method='post' action='/cgi-bin/admin.pl' style='display:inline'>"
            . "<input type='hidden' name='member' value=\"" . ai_esc($in{'member'}) . "\">"
            . "<input type='hidden' name='id' value=\"" . ai_esc($in{'id'}) . "\">"
            . "<input type='hidden' name='l1' value=\"" . ai_esc($in{'l1'}) . "\">"
            . "<input type='hidden' name='l2' value=\"" . ai_esc($in{'l2'}) . "\">"
            . "<input type='hidden' name='l3' value=\"" . ai_esc($in{'l3'}) . "\">"
            . "<input type='hidden' name='action' value=\"" . ai_esc($in{'action'}) . "\">"
            . "<input type='hidden' name='ollama_pull' value='1'>"
            . "<input id='ollama_model_fld' type='text' name='ollama_model' value='qwen2.5:7b' style='width:180px' title='model tag, e.g. qwen2.5:7b, mistral, phi4-mini'>"
            . " <input type='submit' value='Pull model' style='padding:2px 8px'></form>"
            . "<div style='margin-top:2px'>quick pick: $quick_html</div>"
            . "<div style='margin-top:2px'>with vision: $quick_vision_html</div>"
            . "<div style='color:#888;font-size:11px;margin-top:2px'>Ollama endpoint: $ollama_base_env "
            . "(override with env OLLAMA_BASE). Pull downloads run in the background and can take "
            . "several minutes to tens of minutes depending on model size and link speed -- status is shown below once started.</div>";
    }
    my $settings_link = "/cgi-bin/admin.pl?id=" . ai_esc($in{'id'}) . "&amp;member=" . ai_esc($member || '')
        . "&amp;l1=10&amp;l2=05&amp;l3=12";
    my $ai_rows = "<tr style='background:#eee'><th style='text-align:left;padding:4px 8px'>Local AI</th>"
        . "<th style='text-align:left;padding:4px 8px'>Status</th>"
        . "<th style='text-align:left;padding:4px 8px'>Download / configure</th></tr>\n"
        . "<tr><td style='padding:4px 8px'>Ollama (local LLM)<br><span style='color:#888;font-size:11px'>Download/install Ollama and pull a local model for the AI Helpdesk. The cs-aihelp daemon itself is managed under System &gt; Services &gt; AI Helpdesk.</span></td>"
        . "<td style='padding:4px 8px'>$ollama_status<br><span style='color:#888;font-size:11px'>$ollama_models_html</span></td>"
        . "<td style='padding:4px 8px'>$ollama_dl<br><br>$pull_form<br><br><a href=\"$settings_link\"><b>AI Helpdesk settings</b></a></td></tr>\n";
    print "<b>AI Helpdesk (local)</b><br>\n";
    print "<table width='100%' style='border-collapse:collapse;border:1px solid #ccc'>$ai_rows</table>\n";

    # -------------------------------------------- live pull status (cs_26.08.25)
    # shows what ai_ollama_pull_bg() is actually doing for the most recently
    # requested model (passed through as ?pull_model=... after the redirect
    # above), and auto-refreshes the page while it's still running.
    my $watch_model = ai_trim($in{'pull_model'} // '');
    $watch_model =~ s/[^A-Za-z0-9:._-]//g;
    if ($watch_model ne '') {
        my @st = ai_ollama_pull_status($watch_model);
        if (@st) {
            my ($state, $age, $smsg) = @st;
            my %box = (
                starting => ['#fffbe0', '#e0c060', 'starting'],
                pulling  => ['#fffbe0', '#e0c060', 'pulling'],
                done     => ['#dfd',    '#6a6',    'done'],
                error    => ['#fee',    '#faa',    'error'],
            );
            my $b = $box{$state} || ['#eee', '#ccc', $state];
            print "<br><div style='background:$b->[0];border:1px solid $b->[1];border-radius:4px;padding:6px 10px;display:inline-block'>"
                . "<b>pull '" . ai_esc($watch_model) . "': $b->[2]</b>"
                . " (" . $age . "s ago) -- " . ai_esc($smsg) . "</div><br>\n";
            if ($state eq 'starting' || $state eq 'pulling') {
                my $refresh = "$base&pull_model=" . ai_esc($watch_model);
                print "<script>setTimeout(function(){ window.location.href=\"$refresh\"; }, 4000);</script>\n";
            }
        }
    }
    print "<br>\n";

    print "<span style='color:#888;font-size:11px'>"
        . "Only the binary for the frontend OS is downloaded. The OS structure "
        . "(_my/tools/&lt;tool&gt;/&lt;platform&gt;.&lt;arch&gt;/) is kept, so csweb-gui/data can be copied to another OS "
        . "-- there the matching binary is resolved and can be fetched here if missing. "
        . "Newest versions are cached for 1 h (_cfg/cstools_versions).</span><br>\n";

    &log_end;
} #/ my_action

1;
