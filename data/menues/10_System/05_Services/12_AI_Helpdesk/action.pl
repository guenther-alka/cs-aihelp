#!
use strict;

################
# AI Helpdesk -- settings (System > Services > AI Helpdesk)
# (c) napp-it.org 2026
#
# Reads/writes /opt/csweb-gui/_cfg/cs-aihelp (flat key = value file,
# same pattern as the cs-sleeper service config). mode=free (default)
# works out of the box via Pollinations.AI -- free, no account, no key.
# mode=provider uses a user-configured endpoint + API key.
#
# Shared helpers: aihelplib.pl (config load/save, provider presets, chat UI).
# See data/howto.ai/ai-helpdesk.info for the full module documentation.

sub my_action {

    my ($out, $var);

    eval { &mylib_menue_system };
    &load_lib('aihelplib.pl');

    my $member = $in{'member'};
    my $base   = "/cgi-bin/admin.pl?id=$in{'id'}&member=$in{'member'}&l1=$in{'l1'}&l2=$in{'l2'}&l3=$in{'l3'}";

    print "<script language='javascript'>\$('#hl').html('AI Helpdesk -- $member')</script>\n";

    my %aicfg = ai_cfg_read();

    # ------------------------------------------------- daemon start/stop (L2)
    if (($in{'daemon'} // '') =~ /^(start|stop)$/) {
        my $w   = (defined $wpath && $wpath ne '') ? $wpath : '/opt/csweb-gui';
        my $bin = ai_daemon_bin();
        my $out = (-f $bin)
            ? `"$bin" $1 --config "$w/_cfg/cs-aihelp" 2>&1`
            : 'cs-aihelp daemon not installed -- download it under About > CS Tools Download';
        $out = ai_trim($out // '');
        print "<div style='color:#060;background:#dfd;border:1px solid #6a6;border-radius:4px;padding:6px 10px;display:inline-block'>"
            . ai_esc($out) . "</div><br><br>\n";
        print "<script>setTimeout(function(){ window.location.href=\"$base\"; }, 1500);</script>\n";
        &log_end;
        return;
    }

    # ------------------------------------------------- ollama start/stop (Local AI)
    if (($in{'ollama'} // '') =~ /^(start|stop)$/) {
        my ($ok, $msg) = ($1 eq 'start') ? ai_ollama_run() : ai_ollama_stop();
        print "<div style='color:#060;background:#dfd;border:1px solid #6a6;border-radius:4px;padding:6px 10px;display:inline-block'>"
            . ai_esc($msg) . "</div><br><br>\n";
        print "<script>setTimeout(function(){ window.location.href=\"$base\"; }, 1500);</script>\n";
        &log_end;
        return;
    }

    # ---------------------------------------------------------------- save
    if ($in{'answered'}) {
        my %kv;
        $kv{mode}       = ai_trim($in{'cfg_mode'}      // 'free');
        $kv{provider}   = ai_trim($in{'cfg_provider'}  // 'openai');
        $kv{endpoint}   = ai_trim($in{'cfg_endpoint'}  // '');
        $kv{model}      = ai_trim($in{'cfg_model'}     // '');
        $kv{api_key}    = ai_trim($in{'cfg_api_key'}   // '');
        $kv{mode2}      = ai_trim($in{'cfg_mode2'}     // '');
        $kv{provider2}  = ai_trim($in{'cfg_provider2'} // 'openai');
        $kv{endpoint2}  = ai_trim($in{'cfg_endpoint2'} // '');
        $kv{model2}     = ai_trim($in{'cfg_model2'}    // '');
        $kv{api_key2}   = ai_trim($in{'cfg_api_key2'}  // '');
        $kv{free_model2}= ai_trim($in{'cfg_free_model2'} // '');
        # Provider3 = vision provider for the Media Indexer job (cs-imageindex),
        # same layout as Provider1/2 (mode3/provider3 hidden fields + key
        # popup). Empty api_key3 keeps the current value (key store fallback:
        # cs-aihelp-provider-keys.txt, see job-index.pl vision_provider3_cfg).
        $kv{mode3}      = ai_trim($in{'cfg_mode3'}      // '');
        $kv{provider3}  = ai_trim($in{'cfg_provider3'}  // 'openai');
        $kv{endpoint3}  = ai_trim($in{'cfg_endpoint3'}  // '');
        $kv{model3}     = ai_trim($in{'cfg_model3'}     // '');
        # cs_26.08.29: Provider3 API key behaves like Provider1/2 -- a new key
        # from the popup is persisted to the per-endpoint key store AND the
        # config; empty keeps the key-store value for endpoint3 / current key.
        # (key-store save/lookup below, after $preset_name_for is defined)
        $kv{api_key3}   = ai_trim($in{'cfg_api_key3'}   // '');
        $kv{exec_mode}  = ai_trim($in{'cfg_exec_mode'} // 'confirm');
        $kv{exec_access}= ai_trim($in{'cfg_exec_access'} // 'ro');
        $kv{exec_allow} = ai_trim($in{'cfg_exec_allow'} // '');
        $kv{exec_deny}  = ai_trim($in{'cfg_exec_deny'} // 'zfs destroy|zpool destroy|rm -rf|dd |mkfs|format');
        $kv{autostart}  = ai_trim($in{'cfg_autostart'} // 'on');
        $kv{tool_use}   = ai_trim($in{'cfg_tool_use'}  // 'no');
        $kv{history}    = ai_trim($in{'cfg_history'} // 'month');
        my $ht = ai_trim($in{'cfg_history_turns'} // '10');
        $kv{history_turns} = ($ht =~ /^\d+$/ && $ht > 0) ? $ht : '10';
        $kv{free_model} = ai_trim($in{'cfg_free_model'} // '');
        # cs_26.08.25 (Gea: "openai hat kein free provider, openrouter aber
        # schon?" -- integrate OpenRouter as a 3rd mode=free fallback leg,
        # opt-in via key like api_key/api_key2: needs a free openrouter.ai
        # account, so unlike Ollama/Pollinations it's not on by default).
        $kv{openrouter_key}   = ai_trim($in{'cfg_openrouter_key'}   // '');
        $kv{openrouter_model} = ai_trim($in{'cfg_openrouter_model'} // '');
        $kv{widget}     = ai_trim($in{'cfg_widget'} // 'on');
        my $il = ai_trim($in{'cfg_widget_input_lines'} // '1');
        $kv{widget_input_lines} = ($il =~ /^\d+$/ && $il >= 1 && $il <= 10) ? $il : '1';
        my $ah = ai_trim($in{'cfg_widget_answer_height'} // '220');
        $kv{widget_answer_height} = ($ah =~ /^\d+$/ && $ah >= 100 && $ah <= 1200) ? $ah : '220';
        $kv{research}   = ai_trim($in{'cfg_research'} // 'ddg');
        my $rm = ai_trim($in{'cfg_research_max'} // '5');
        $kv{research_max} = ($rm =~ /^\d+$/ && $rm > 0) ? $rm : '5';
        # cs_26.08.26_3 (Gea KISS: "research endpoint: es gibt nur noch
        # provider wahl, keine manuelle eintraege, kann weg" + "Fallback:
        # nein, entweder ein provider funktioniert oder eben nicht") --
        # both fields removed from the UI; forced here regardless of any
        # stray form data, not just defaulted, so old bookmarked/scripted
        # posts can't resurrect them either. research_endpoint/research_key
        # stay in the config schema (Go daemon still reads them) but are no
        # longer reachable via Settings -- "Web research" below only offers
        # off|ddg now (no more research=api option). Daemon-side fallback
        # logic removal is a separate step (Go source, v1.2) after this UI
        # pass is confirmed working.
        $kv{research_endpoint} = '';
        $kv{research_key}      = '';
        $kv{fallback}          = 'off';
        $kv{log}               = ai_trim($in{'cfg_log'} // 'on');
        $kv{ssrf_allow_private}= ai_trim($in{'cfg_ssrf_allow_private'} // 'no');
        my $rl = ai_trim($in{'cfg_rate_limit'} // '60');
        $kv{rate_limit}        = ($rl =~ /^\d+$/ && $rl >= 0) ? $rl : '60';
        my $mc = ai_trim($in{'cfg_max_context'} // '');
        $kv{max_context} = ($mc =~ /^\d+$/ && $mc > 0) ? $mc : '8000';
        # cs_26.08.26_2 (Gea: "provider preset+endpoint+api speichern, dann
        # waer der bei providerwechsel direkt verfuegbar"): if a NEW key was
        # typed, remember it for this endpoint in the separate (never-shared)
        # cs-aihelp-provider-keys.txt; if the field was left empty, first try
        # to restore a previously-saved key for the (possibly just-changed,
        # e.g. via preset) endpoint before falling back to "keep whatever was
        # already configured" (the old, endpoint-agnostic behavior).
        my $preset_name_for = sub {
            my ($endpoint) = @_;
            for my $p (@{ ai_provider_presets() }) {
                return $p->{name} if $p->{endpoint} eq $endpoint;
            }
            return '';
        };
        if ($kv{api_key} ne '') {
            ai_provider_key_save($kv{endpoint}, $preset_name_for->($kv{endpoint}), $kv{api_key});
        } else {
            my $saved = ai_provider_key_lookup($kv{endpoint});
            $kv{api_key} = ($saved ne '') ? $saved : ($aicfg{api_key} // '');
        }
        if ($kv{api_key2} ne '') {
            ai_provider_key_save($kv{endpoint2}, $preset_name_for->($kv{endpoint2}), $kv{api_key2});
        } else {
            my $saved2 = ai_provider_key_lookup($kv{endpoint2});
            $kv{api_key2} = ($saved2 ne '') ? $saved2 : ($aicfg{api_key2} // '');
        }
        if ($kv{api_key3} ne '') {
            ai_provider_key_save($kv{endpoint3}, $preset_name_for->($kv{endpoint3}), $kv{api_key3});
        } else {
            my $saved3 = ai_provider_key_lookup($kv{endpoint3});
            $kv{api_key3} = ($saved3 ne '') ? $saved3 : ($aicfg{api_key3} // '');
        }
        $kv{openrouter_key} = $aicfg{openrouter_key} if $kv{openrouter_key} eq '';

        my $ok = ai_cfg_write(%kv);
        # cs_26.08.26_10 (Gea: "was ist smb? -- reagiert immer noch nicht
        # (deepseek, mode 2)") -- ai_cfg_write() only rewrites the file; the
        # already-running daemon kept using its in-memory config from when
        # it started (confirmed live: still connected to Ollama minutes
        # after switching to OpenRouter/DeepSeek here). Tell it to pick up
        # the new file immediately instead of requiring a manual daemon
        # Stop/Start. Best-effort: a save is still reported as successful
        # even if the daemon is currently down (it'll read the new config
        # whenever it next starts) or the reload call itself fails.
        my $reloaded = $ok ? ai_daemon_reload() : 0;
        print (($ok
            ? "<div style='color:#060;background:#dfd;border:1px solid #6a6;border-radius:4px;padding:6px 10px;display:inline-block'>"
                . ai_txt('ai_saved', 'AI Helpdesk settings saved.')
                . ($reloaded ? '' : ' ' . ai_txt('ai_reload_failed', '(daemon not reachable -- restart it manually via Stop/Start above to apply)'))
                . "</div>"
            : "<div style='color:#a00;background:#fee;border:1px solid #faa;border-radius:4px;padding:6px 10px;display:inline-block'>"
                . ai_txt('ai_save_failed', 'Error writing config file') . " " . ai_esc(ai_cfg_path()) . "</div>")
            . "<br><br>\n");
        %aicfg = ai_cfg_read();
        print "<script>setTimeout(function(){ window.location.href=\"$base\"; }, 1500);</script>\n";
        &log_end;
        return;
    }

    # ------------------------------------------------------------ status
    my $mode_html = { off      => "<span style='color:#888'>off</span>",
                      free     => "<span style='color:darkgreen'><b>free</b></span> (no key, works out of the box)",
                      provider => "<span style='color:#234'><b>provider</b></span>" }->{ $aicfg{mode} // 'off' }
                  // "<span style='color:#888'>" . ai_esc($aicfg{mode} // 'off') . "</span>";
    my $resolved = ai_resolve(%aicfg);
    my $ep_html  = $resolved ? "<span style='font-family:monospace;font-size:12px'>" . ai_esc($resolved->{endpoint} // '') . "</span>"
                            : '<i>no endpoint (off)</i>';
    my $listen_html = "<span style='font-family:monospace;font-size:12px'>" . ai_esc(ai_trim($aicfg{listen} // '127.0.0.1:45555')) . "</span>";

    # daemon binary status (cs-aihelp is NOT bundled; downloaded via
    # About > CS Tools Download -- start/stop happens here).
    my ($d_bin, $d_ver) = ai_daemon_status();
    my $daemon_html;
    if ($d_bin) {
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
        $daemon_html = "<span style='color:darkgreen'><b>installed</b></span> " . ai_esc($d_ver)
            . " &nbsp; " . $daemon_form->('start', 'Start') . ' ' . $daemon_form->('stop', 'Stop');
    } else {
        # cs_26.08.25: CS Tools Download moved from System to About
        my $cs_tools_link = "/cgi-bin/admin.pl?id=" . ai_esc($in{'id'}) . "&amp;member=" . ai_esc($member || '')
            . "&amp;l1=00_about&amp;l2=08_cs_tools_download";
        print "<div style='color:#a00;background:#fee;border:1px solid #faa;border-radius:4px;padding:6px 10px;display:inline-block'>"
            . "cs-aihelp daemon not installed -- please download CS tools first: "
            . "<a href=\"$cs_tools_link\"><b>About &gt; CS Tools Download</b></a></div><br><br>\n";
        $daemon_html = "<span style='color:#a00'><b>not installed</b></span> (see About &gt; CS Tools Download)";
    }

    # ---- risk warning: exec (D2) + web research active at the same time ----
    # Web research / live tool-use results are fed to the model as untrusted
    # DATA; if exec_access != ro the model can turn its own answer into a
    # proposed command. Combining both raises the prompt-injection blast
    # radius noticeably, especially with exec_mode=auto (no human review).
    my $exa = ai_trim($aicfg{exec_access} // 'ro');
    my $res = ai_trim($aicfg{research}    // 'ddg');
    if ($exa ne 'ro' && $res ne 'off') {
        my $em = ai_trim($aicfg{exec_mode} // 'confirm');
        print "<div style='color:#7a5b00;background:#fff6df;border:1px solid #e0c060;border-radius:4px;padding:6px 10px;display:inline-block;max-width:780px'>"
            . "<b>Warning:</b> Exec access (<code>exec_access=$exa</code>) and web research (<code>research=$res</code>) "
            . "are both active. Search results / live state reach the model as untrusted data; if the model turns that "
            . "into a proposed command, it is executed" . ($em eq 'auto' ? " <b>without confirmation (exec_mode=auto)</b>" : " after your \"" . ai_esc($em) . "\" confirmation") . ". "
            . "Consider <code>research=off</code> while <code>exec_access=exec/console</code>, or keep <code>exec_mode=confirm</code>."
            . "</div><br><br>\n";
    }

    # ---- Local AI (Ollama) status ----
    my ($ollama_models, $ollama_ok) = ai_ollama_models();
    my $ollama_ver   = ai_ollama_version();
    my $ollama_state = $ollama_ok
        ? "<span style='color:darkgreen'><b>running</b></span>"
        : "<span style='color:#a00'><b>not running</b></span>";
    my $ollama_form = sub {
        my ($cmd, $label) = @_;
        return "<form method='post' action='/cgi-bin/admin.pl' style='display:inline'>"
            . "<input type='hidden' name='member' value=\"" . ai_esc($in{'member'}) . "\">"
            . "<input type='hidden' name='id' value=\"" . ai_esc($in{'id'}) . "\">"
            . "<input type='hidden' name='l1' value=\"" . ai_esc($in{'l1'}) . "\">"
            . "<input type='hidden' name='l2' value=\"" . ai_esc($in{'l2'}) . "\">"
            . "<input type='hidden' name='l3' value=\"" . ai_esc($in{'l3'}) . "\">"
            . "<input type='hidden' name='action' value=\"" . ai_esc($in{'action'}) . "\">"
            . "<input type='hidden' name='ollama' value=\"" . ai_esc($cmd) . "\">"
            . "<input type='submit' value=\"" . ai_esc($label) . "\"></form>";
    };
    my $ollama_html = ($ollama_ver ne '' ? ai_esc($ollama_ver) . ' &nbsp; ' : '')
        . $ollama_state . " &nbsp; "
        . $ollama_form->('start', 'Start') . ' ' . $ollama_form->('stop', 'Stop');
    my $ollama_base = $ENV{OLLAMA_BASE} // 'http://127.0.0.1:11434';

    # ---- hand-rolled 100%-width tables (list2table's first width segment
    # doubles as the outer <table> width AND a column width, which makes a
    # true 100% layout unreliable -- same pattern already used successfully
    # in _lib/tools/CS_Tools_Download/action.pl) ----
    my $tbl_open  = "<table width='100%' style='border-collapse:collapse;border:1px solid #ccc'>\n";
    my $tbl_close = "</table>\n";
    my $row2 = sub {
        my ($label, $val) = @_;
        return "<tr><td style='padding:4px 8px;width:200px;vertical-align:top'><b>$label</b></td>"
             . "<td style='padding:4px 8px'>$val</td></tr>\n";
    };
    # gray, full-width header row inside each table (structures the page --
    # 5 sections total: Local AI, CS-AI Helpdesk status, then general /
    # Provider1 / Provider2 config tables further down).
    my $hdr_row = sub {
        my ($title) = @_;
        return "<tr><td colspan='2' style='background:#e0e0e0;padding:6px 8px;font-weight:bold;border-bottom:1px solid #ccc'>$title</td></tr>\n";
    };

    # ---- table 1: Local AI (Ollama) ----
    print $tbl_open;
    print $hdr_row->('Local AI -Ollama-');
    print $row2->('Ollama', $ollama_html);
    print $row2->('Base', "<span style='font-family:monospace;font-size:12px'>" . ai_esc($ollama_base) . "</span> (OLLAMA_BASE)");
    print $tbl_close;
    print "<br>\n";

    # ---- table 2: CS-AI Daemon (the napp-it service) -- daemon status
    # (running/stopped, probed live via ai_daemon_running()) shown before
    # the Start/Stop buttons, not just "installed" (binary-on-disk check).
    my $daemon_status_html = $d_bin
        ? (ai_daemon_running()
            ? "<span style='color:darkgreen'><b>running</b></span> &nbsp; "
            : "<span style='color:#a00'><b>stopped</b></span> &nbsp; ")
        : '';
    print $tbl_open;
    print $hdr_row->('CS-AI Daemon');
    print $row2->('Daemon', $daemon_status_html . $daemon_html);
    print $row2->('Config', ai_esc(ai_cfg_path()));
    print $row2->('Mode', $mode_html);
    print $row2->('AI endpoint', $ep_html);
    print $row2->('Daemon listen', $listen_html);
    print $tbl_close;
    print "<br>\n";

    # --------------------------------------------------------------- form
    my $sel = sub {
        my ($name, $cur, @opts) = @_;
        my $h = "<select name='$name' id='$name' style='width:200px'>";
        for my $o (@opts) {
            $h .= "<option value='$o'" . (($cur eq $o) ? " selected" : "") . ">$o</option>";
        }
        return $h . "</select>";
    };
    my $desc = sub {
        return "<span style='color:#888;font-size:11px'>" . $_[0] . "</span>";
    };

    print "<form method='post' action='/cgi-bin/admin.pl'>";
    print "<input type='hidden' name='member' value=\"" . ai_esc($in{'member'}) . "\">\n";
    print "<input type='hidden' name='id' value=\"" . ai_esc($in{'id'}) . "\">\n";
    print "<input type='hidden' name='l1' value=\"" . ai_esc($in{'l1'}) . "\">\n";
    print "<input type='hidden' name='l2' value=\"" . ai_esc($in{'l2'}) . "\">\n";
    print "<input type='hidden' name='l3' value=\"" . ai_esc($in{'l3'}) . "\">\n";
    print "<input type='hidden' name='action' value=\"" . ai_esc($in{'action'}) . "\">\n";
    print "<input type='hidden' name='answered' value='1'>\n";

    # ---- unified Provider select (slot 1 + slot 2) ------------------------
    # cs_26.08.26_3 (Gea KISS redesign): "Provider preset" + "Mode 1" +
    # "Provider" + "Endpoint" collapse into ONE select per slot -- picking a
    # preset IS the provider choice now (protocol+endpoint come straight
    # from _cfg/cs-aihelp-providers.txt, no manual URL entry anywhere).
    # "Free model" / "OpenRouter key" / "OpenRouter model" are gone --
    # "Ollama (local)" is just a normal, keyless preset entry now. "Model"
    # is a live <select> fetched from the provider's own /models API
    # (get_async.pl area=ai subarea=models -> ai_list_provider_models() in
    # aihelplib.pl) instead of a free-text field, showing "api not
    # accepted" when the key/endpoint doesn't work. Presets with an
    # already-saved key are sorted first and marked, so re-picking a
    # previously-configured provider needs zero retyping.
    my $presets = ai_provider_presets();
    my $key_saved_for = sub {
        my ($ep) = @_;
        return ($ep ne '' && ai_provider_key_lookup($ep) ne '') ? 1 : 0;
    };
    my $preset_by_endpoint = sub {
        my ($ep) = @_;
        return undef unless $ep ne '';
        for my $p (@$presets) { return $p if $p->{endpoint} eq $ep; }
        return undef;
    };
    # cs_26.08.26_3 fix (found via test harness, live config
    # mode=provider/provider=ollama/endpoint='' on this box): a stored
    # endpoint of '' means "use ai_resolve()'s per-protocol default", NOT
    # "no endpoint" -- matching raw endpoint='' against the preset list
    # always missed, silently pre-selecting "off" for an actually-working
    # config. Mirror ai_resolve()'s own %default_ep (only openai/anthropic/
    # ollama/openrouter have one -- any other provider value with an empty
    # endpoint was never resolvable before this redesign either) so the
    # pre-select reflects what's ACTUALLY in effect, not just what's
    # literally stored.
    my %legacy_default_ep = (
        openai     => 'https://api.openai.com/v1/chat/completions',
        anthropic  => 'https://api.anthropic.com/v1/messages',
        ollama     => 'http://127.0.0.1:11434/api/chat',
        openrouter => 'https://openrouter.ai/api/v1/chat/completions',
    );

    # returns ($select_html_incl_hidden_fields, $key_row_html, $model_select_html)
    my $provider_block = sub {
        my ($slot, $cur_mode, $cur_provider, $cur_endpoint, $cur_model) = @_;
        my $sfx = ($slot == 3) ? '3' : (($slot == 2) ? '2' : '');
        my $effective_endpoint = ($cur_endpoint ne '') ? $cur_endpoint : ($legacy_default_ep{$cur_provider} // '');
        my $cur_preset = $preset_by_endpoint->($effective_endpoint);
        my $cur_val = 'off';
        if    ($slot == 2 && $cur_mode eq '')          { $cur_val = ''; }
        elsif ($cur_mode eq 'provider' && $cur_preset) { $cur_val = $cur_preset->{name}; }
        # mode=free or an unmatched custom endpoint from before this redesign
        # falls back to "off" in the new select -- nothing sensible to
        # preselect; pick a preset here to move on.

        my @sorted = sort { $key_saved_for->($b->{endpoint}) <=> $key_saved_for->($a->{endpoint}) } @$presets;

        my $h = "<select name='cfg_choice$slot' id='cfg_choice$slot' onchange='csAiProviderChange($slot)' style='width:100%'>";
        if ($slot == 2) {
            $h .= "<option value=''" . ($cur_val eq '' ? ' selected' : '') . ">(use slot 1)</option>";
        }
        $h .= "<option value='off'" . ($cur_val eq 'off' ? ' selected' : '') . ">off</option>";
        for my $p (@sorted) {
            my $mark = $key_saved_for->($p->{endpoint}) ? '[key saved] ' : '';
            $h .= "<option value='" . ai_esc($p->{name}) . "'"
                . " data-protocol='" . ai_esc($p->{protocol}) . "'"
                . " data-endpoint='" . ai_esc($p->{endpoint}) . "'"
                . " data-keysaved='" . ($key_saved_for->($p->{endpoint}) ? '1' : '0') . "'"
                . (($cur_val eq $p->{name}) ? ' selected' : '')
                . ">" . ai_esc($mark . $p->{name}) . "</option>";
        }
        $h .= "</select>";

        # hidden fields the form actually submits -- key names unchanged
        # from before this redesign, so the Save block above needed no edits.
        my $h_mode     = ($cur_val eq '') ? '' : ($cur_val eq 'off' ? 'off' : 'provider');
        my $h_provider = $cur_preset ? $cur_preset->{protocol} : ($cur_provider || 'openai');
        # cs_26.08.26_3: use the PRESET's endpoint (always explicit), not the
        # possibly-empty raw stored value -- a blank endpoint used to mean
        # "ai_resolve() picks a per-protocol default"; going forward every
        # save writes the real URL explicitly (KISS: no more implicit
        # provider-default resolution to reason about).
        my $h_endpoint = ($cur_val eq '' || $cur_val eq 'off') ? '' : ($cur_preset ? $cur_preset->{endpoint} : $cur_endpoint);
        $h .= "<input type='hidden' name='cfg_mode$sfx' id='cfg_mode$sfx' value=\"" . ai_esc($h_mode) . "\">";
        $h .= "<input type='hidden' name='cfg_provider$sfx' id='cfg_provider$sfx' value=\"" . ai_esc($h_provider) . "\">";
        $h .= "<input type='hidden' name='cfg_endpoint$sfx' id='cfg_endpoint$sfx' value=\"" . ai_esc($h_endpoint) . "\">";

        # cs_26.08.26_4 (Gea: Popup statt sichtbarem Passwort-Feld) -- the
        # form never shows or edits the key inline. It shows only "accepted"
        # / "unset" (from ai_provider_key_lookup, same source as the preset's
        # "[key saved]" marker) plus a button that opens a small popup; the
        # popup writes into this hidden field on Save, which the existing
        # Save block below already reads (empty=keep-current, unchanged).
        my $show_key = ($cur_val ne '' && $cur_val ne 'off' && (!$cur_preset || $cur_preset->{protocol} ne 'ollama'));
        my $key_saved_now = (ai_provider_key_lookup($h_endpoint) ne '');
        my $key_html = "<div id='cfg_keyrow$slot' style='" . ($show_key ? '' : 'display:none;') . "margin-top:4px'>"
            . "<input type='hidden' id='cfg_api_key_input$slot' name='cfg_api_key$sfx' value=\"\">"
            . "<span id='cfg_key_status$slot' style='" . ($key_saved_now ? 'color:#060' : 'color:#888') . "'>"
            . ($key_saved_now ? 'accepted' : 'unset') . "</span> &nbsp;"
            . "<button type='button' onclick='csAiKeyPopupOpen($slot)'>change key</button>"
            . $desc->("stored separately in cs-aihelp-provider-keys.txt, never shown here -- "
                . "saved for THIS endpoint immediately, but the AI Helpdesk daemon only reads "
                . "the Settings below \"Save\" button, so click Save once to make it active")
            . "</div>";

        my $model_html = "<select name='cfg_model$sfx' id='cfg_model_select$slot' data-current=\"" . ai_esc($cur_model) . "\" style='width:100%'>";
        $model_html .= ($cur_model ne '')
            ? "<option value='" . ai_esc($cur_model) . "' selected>" . ai_esc($cur_model) . "</option>"
            : "<option value=''>-- select a provider --</option>";
        $model_html .= "</select>" . $desc->("populated live from the provider's own model list; shows \"api not accepted\" on a bad/missing key");

        return ($h, $key_html, $model_html, $h_provider, $h_endpoint);
    };

    my ($prov1_sel, $prov1_key, $prov1_model, $prov1_proto, $prov1_ep) =
        $provider_block->(1, $aicfg{mode} // 'free', $aicfg{provider} // 'openai', $aicfg{endpoint} // '', $aicfg{model} // '');
    my ($prov2_sel, $prov2_key, $prov2_model, $prov2_proto, $prov2_ep) =
        $provider_block->(2, $aicfg{mode2} // '', $aicfg{provider2} // 'openai', $aicfg{endpoint2} // '', $aicfg{model2} // '');
    # Provider3 = vision provider for the Media Indexer job (cs-imageindex),
    # full Provider2-style block (preset list + key popup + live model list).
    my ($prov3_sel, $prov3_key, $prov3_model, $prov3_proto, $prov3_ep) =
        $provider_block->(3, $aicfg{mode3} // '', $aicfg{provider3} // 'openai', $aicfg{endpoint3} // '', $aicfg{model3} // '');

    print "<script>\n";
    print "var CsAi = {id:'" . ai_esc($in{'id'}) . "', mem:'" . ai_esc($in{'member'}) . "'};\n";
    print "function csAiProviderChange(slot){\n";
    print "  var sel=document.getElementById('cfg_choice'+slot); var o=sel.options[sel.selectedIndex];\n";
    print "  var val=sel.value; var proto=o.getAttribute('data-protocol')||''; var ep=o.getAttribute('data-endpoint')||'';\n";
    print "  var keysaved=o.getAttribute('data-keysaved')==='1';\n";
    print "  var sfx=(slot===3)?'3':((slot===2)?'2':'');\n";
    print "  var mf=document.getElementById('cfg_mode'+sfx), pf=document.getElementById('cfg_provider'+sfx), ef=document.getElementById('cfg_endpoint'+sfx);\n";
    print "  if(val===''){ if(mf)mf.value=''; if(pf)pf.value=''; if(ef)ef.value=''; }\n";
    print "  else if(val==='off'){ if(mf)mf.value='off'; if(pf)pf.value=''; if(ef)ef.value=''; }\n";
    print "  else { if(mf)mf.value='provider'; if(pf)pf.value=proto; if(ef)ef.value=ep; }\n";
    print "  var kr=document.getElementById('cfg_keyrow'+slot);\n";
    print "  if(kr) kr.style.display=(val===''||val==='off'||proto==='ollama')?'none':'';\n";
    print "  var kf=document.getElementById('cfg_api_key_input'+slot); if(kf) kf.value='';\n";
    print "  var st=document.getElementById('cfg_key_status'+slot);\n";
    print "  if(st){ st.textContent=keysaved?'accepted':'unset'; st.style.color=keysaved?'#060':'#888'; }\n";
    print "  var ms0=document.getElementById('cfg_model_select'+slot); if(ms0) ms0.setAttribute('data-current','');\n";
    print "  csAiFetchModels(slot, proto, ep);\n";
    print "}\n";
    print "var csAiKeyPopupSlot=null;\n";
    print "function csAiKeyPopupOpen(slot){\n";
    print "  csAiKeyPopupSlot=slot;\n";
    print "  var st=document.getElementById('cfg_key_status'+slot); var saved=st&&st.textContent==='accepted';\n";
    print "  document.getElementById('cfgKeyPopupStatus').textContent=saved\n";
    print "    ?'A key is currently saved for this endpoint. Leave empty and Save to keep it, or enter a new one to replace it.'\n";
    print "    :'No key saved yet for this endpoint.';\n";
    print "  document.getElementById('cfgKeyPopupInput').value='';\n";
    print "  document.getElementById('cfgKeyPopupOverlay').style.display='block';\n";
    print "}\n";
    print "function csAiKeyPopupCancel(){\n";
    print "  document.getElementById('cfgKeyPopupOverlay').style.display='none'; csAiKeyPopupSlot=null;\n";
    print "}\n";
    print "function csAiKeyPopupSave(){\n";
    print "  var slot=csAiKeyPopupSlot; if(!slot) return;\n";
    print "  var val=document.getElementById('cfgKeyPopupInput').value;\n";
    print "  var sfx=(slot===3)?'3':((slot===2)?'2':''); var pf=document.getElementById('cfg_provider'+sfx), ef=document.getElementById('cfg_endpoint'+sfx);\n";
    print "  if(val){\n";
    print "    var kf=document.getElementById('cfg_api_key_input'+slot); if(kf) kf.value=val;\n";
    print "    var st=document.getElementById('cfg_key_status'+slot);\n";
    print "    if(st){ st.textContent='checking...'; st.style.color='#888'; }\n";
    # cs_26.08.26_6 (Gea: "der key sollte per provider gemerkt werden so
    # dass man einfach umschalten kann ohne key erneut einzugeben") --
    # persist the key immediately (area=ai subarea=savekey) instead of
    # waiting for the whole Settings form to be submitted, so switching
    # providers a few times before hitting the page's own Save button
    # still finds the key on the way back. Also mark the currently
    # selected <option> as key-saved so an immediate switch-away-and-back
    # (before the live fetch below even resolves) already shows "accepted"
    # via the optimistic path in csAiProviderChange.
    print "    var sel=document.getElementById('cfg_choice'+slot); var name=sel?sel.value:'';\n";
    print "    if(sel) sel.options[sel.selectedIndex].setAttribute('data-keysaved','1');\n";
    print "    if(ef && ef.value){\n";
    print "      fetch('/cgi-bin/get_async.pl',{method:'POST',headers:{'Content-Type':'application/json'},\n";
    print "        body:JSON.stringify({id:CsAi.id, member:CsAi.mem, area:'ai', subarea:'savekey',\n";
    print "          endpoint:ef.value, name:name, api_key:val, cache:0})\n";
    print "      }).catch(function(){});\n";
    print "    }\n";
    print "  }\n";
    print "  document.getElementById('cfgKeyPopupOverlay').style.display='none';\n";
    print "  if(pf && ef && ef.value) csAiFetchModels(slot, pf.value, ef.value);\n";
    print "  csAiKeyPopupSlot=null;\n";
    print "}\n";
    print "function csAiFetchModels(slot, proto, ep){\n";
    print "  var ms=document.getElementById('cfg_model_select'+slot); if(!ms) return;\n";
    print "  if(!ep||!proto){ ms.innerHTML=\"<option value=''>-- select a provider --</option>\"; return; }\n";
    print "  ms.innerHTML=\"<option value=''>loading...</option>\";\n";
    print "  var kf=document.getElementById('cfg_api_key_input'+slot);\n";
    print "  fetch('/cgi-bin/get_async.pl',{method:'POST',headers:{'Content-Type':'application/json'},\n";
    print "    body:JSON.stringify({id:CsAi.id, member:CsAi.mem, area:'ai', subarea:'models',\n";
    print "      protocol:proto, endpoint:ep, api_key:(kf?kf.value:''), cache:0})\n";
    print "  }).then(function(r){return r.json();}).then(function(j){\n";
    print "    ms.innerHTML='';\n";
    print "    var cur=ms.getAttribute('data-current')||'';\n";
    print "    var ok = j.ok && j.detail && j.detail.models && j.detail.models.length;\n";
    print "    if(ok){\n";
    print "      j.detail.models.forEach(function(m){ var o=document.createElement('option'); o.value=m; o.textContent=m+((j.detail.vision&&j.detail.vision[m])?' (vision)':''); if(m===cur) o.selected=true; ms.appendChild(o); });\n";
    print "    } else {\n";
    print "      var o=document.createElement('option'); o.value=cur; o.textContent=(j.text||'api not accepted')+(cur?' ('+cur+' kept)':''); o.selected=true; ms.appendChild(o);\n";
    print "    }\n";
    print "    var st=document.getElementById('cfg_key_status'+slot);\n";
    print "    if(st && proto!=='ollama'){\n";
    print "      if(ok){ st.textContent='accepted'; st.style.color='#060'; }\n";
    print "      else if(j.text==='no key configured'){ st.textContent='unset'; st.style.color='#888'; }\n";
    print "      else { st.textContent='refused'; st.style.color='#a00'; }\n";
    print "    }\n";
    print "  }).catch(function(){\n";
    print "    var cur=ms.getAttribute('data-current')||'';\n";
    print "    ms.innerHTML=\"<option value='\"+cur+\"' selected>network error\"+(cur?' ('+cur+' kept)':'')+\"</option>\";\n";
    print "    var st=document.getElementById('cfg_key_status'+slot);\n";
    print "    if(st && proto!=='ollama'){ st.textContent='refused'; st.style.color='#a00'; }\n";
    print "  });\n";
    print "}\n";
    # cs_26.08.26_5 (Gea: "bei Ollama lokal keine Modellauswahl?") -- the
    # Model select only ever populated on an onchange event; a page reload
    # with an already-configured provider (Ollama or cloud) showed just the
    # single stored model value, not the live list, until you re-touched
    # the dropdown. Auto-fetch both slots once on load instead -- for
    # Ollama this is instant/local; for a cloud provider with a saved key,
    # get_async.pl's _h_ai_models already falls back to the stored key when
    # api_key is sent empty, so this also gives immediate accepted/refused
    # feedback without the user opening the key popup at all.
    print "(function(){\n";
    print "  var p1=document.getElementById('cfg_provider'), e1=document.getElementById('cfg_endpoint');\n";
    print "  if(p1 && e1 && p1.value && e1.value) csAiFetchModels(1, p1.value, e1.value);\n";
    print "  var m2=document.getElementById('cfg_mode2'), p2=document.getElementById('cfg_provider2'), e2=document.getElementById('cfg_endpoint2');\n";
    print "  if(m2 && m2.value==='provider' && p2.value && e2.value) csAiFetchModels(2, p2.value, e2.value);\n";
    print "  var m3=document.getElementById('cfg_mode3'), p3=document.getElementById('cfg_provider3'), e3=document.getElementById('cfg_endpoint3');\n";
    print "  if(m3 && m3.value==='provider' && p3.value && e3.value) csAiFetchModels(3, p3.value, e3.value);\n";
    print "})();\n";
    print "</script>\n";

    # single reusable popup for both provider slots (cs_26.08.26_4)
    print "<div id='cfgKeyPopupOverlay' style='display:none;position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.4);z-index:1000'>"
        . "<div style='background:#fff;max-width:400px;margin:100px auto;padding:16px;border-radius:6px;border:1px solid #ccc'>"
        . "<div id='cfgKeyPopupStatus' style='margin-bottom:8px;font-size:12px;color:#888'></div>"
        . "<input type='password' id='cfgKeyPopupInput' style='width:100%' placeholder='new API key' autocomplete='off'>"
        . "<div style='margin-top:12px;text-align:right'>"
        . "<button type='button' onclick='csAiKeyPopupCancel()'>Cancel</button> "
        . "<button type='button' onclick='csAiKeyPopupSave()'>Save key</button>"
        . "</div></div></div>\n";

    my @prov1 = (
        [ 'Provider',    $prov1_sel . $desc->("off | a preset from _cfg/cs-aihelp-providers.txt (edit that file to add/remove presets)") ],
        [ 'API key',     $prov1_key ],
        [ 'Model',       $prov1_model ],
    );
    my @prov2 = (
        [ 'Provider 2',  $prov2_sel . $desc->("(use slot 1) | off | a preset -- optional 2nd provider for the act/exec step") ],
        [ 'API key 2',   $prov2_key ],
        [ 'Model 2',     $prov2_model ],
    );

    # ---- Provider3: vision provider for the Media Indexer job (cs-imageindex) ----
    # cs_26.08.29 (Gea: "keine provider3 settings fuer cs-imageindex") -- the
    # Media Indexer job reads endpoint3/model3/api_key3 (see job-index.pl
    # vision_provider3_cfg). Full Provider2-style block: preset list from
    # _cfg/cs-aihelp-providers.txt, key via the popup / key store, live model
    # list from the endpoint.
    my @prov3 = (
        [ 'Provider 3',  $prov3_sel . $desc->("off | a preset -- vision provider used by the Media Indexer job (cs-imageindex) for scene descriptions") ],
        [ 'API key 3',   $prov3_key ],
        [ 'Model 3',     $prov3_model ],
    );

    # ---- general CS AI Helpdesk options (everything not provider-slot-specific) ----
    my @general = (
        [ 'Daemon autostart',    $sel->('cfg_autostart', $aicfg{autostart} // 'on', qw(on off)) . $desc->("on = Go daemon starts with server.pl") ],
        [ 'Tool use (L1)',       $sel->('cfg_tool_use', $aicfg{tool_use} // 'no', qw(no yes)) . $desc->("yes = read-only system context (hostname, zpool) for AI answers -- not the daemon start") ],
        [ 'Exec access (L2)',    $sel->('cfg_exec_access', $aicfg{exec_access} // 'ro', qw(ro exec console)) . $desc->("ro | exec | console") ],
        [ 'Exec mode (L2)',      $sel->('cfg_exec_mode', $aicfg{exec_mode} // 'confirm', qw(propose confirm auto)) . $desc->("propose | confirm | auto") ],
        [ 'Exec allow (D2)',     "<input type='text' name='cfg_exec_allow' value=\"" . ai_esc($aicfg{exec_allow} // '')
                                 . "\" style='width:100%' placeholder='e.g. zfs,zpool,find,curl,ls,grep'>" . $desc->("comma list of allowed commands; empty = nothing") ],
        [ 'Exec deny (always)',  "<input type='text' name='cfg_exec_deny' value=\"" . ai_esc($aicfg{exec_deny} // 'zfs destroy|zpool destroy|rm -rf|dd |mkfs|format')
                                 . "\" style='width:100%'>" . $desc->("always applied (wins)") ],
        [ 'History',             $sel->('cfg_history', $aicfg{history} // 'month', qw(off today week month 6months all)) . $desc->("off | today | week | month | 6months | all") ],
        [ 'History turns',       "<input type='text' name='cfg_history_turns' value=\"" . ai_esc($aicfg{history_turns} // '10')
                                 . "\" style='width:80px'>" . $desc->("prior turns as context") ],
        [ 'Widget (popup)',      $sel->('cfg_widget', $aicfg{widget} // 'on', qw(on off)) . $desc->("on = popup | off = page only") ],
        [ 'Popup input lines',   "<input type='text' name='cfg_widget_input_lines' value=\"" . ai_esc($aicfg{widget_input_lines} // '1')
                                 . "\" style='width:80px'>" . $desc->("1-10") ],
        [ 'Popup answer height (px)', "<input type='text' name='cfg_widget_answer_height' value=\"" . ai_esc($aicfg{widget_answer_height} // '220')
                                 . "\" style='width:80px'>" . $desc->("px (100-1200)") ],
        [ 'Web research',        $sel->('cfg_research', ((($aicfg{research} // 'ddg') eq 'api') ? 'ddg' : ($aicfg{research} // 'ddg')), qw(off ddg))
                                 . $desc->("off | ddg (DuckDuckGo, no key) -- custom search API removed, see KISS note below") ],
        [ 'Research results',    "<input type='text' name='cfg_research_max' value=\"" . ai_esc($aicfg{research_max} // '5')
                                 . "\" style='width:80px'>" . $desc->("max. results") ],
        [ 'Logging',             $sel->('cfg_log', $aicfg{log} // 'on', qw(on off)) . $desc->("on | off") ],
        [ 'SSRF private EP',     $sel->('cfg_ssrf_allow_private', $aicfg{ssrf_allow_private} // 'no', qw(no yes)) . $desc->("yes | no") ],
        [ 'Rate limit (daemon)', "<input type='text' name='cfg_rate_limit' value=\"" . ai_esc($aicfg{rate_limit} // '60')
                                 . "\" style='width:80px'>" . $desc->("req/min (0 = off)") ],
        [ 'Context budget',      "<input type='text' name='cfg_max_context' value=\"" . ai_esc($aicfg{max_context} // '8000')
                                 . "\" style='width:80px'>" . $desc->("chars") ],
    );

    # ---- render: 3 separate, full-width, stacked 2-column tables (general /
    # Provider1 / Provider2) -- the earlier 4-column row-zip (general +
    # Provider1 + Provider2 side by side) was reported as cluttered/unclear,
    # so each section is now its own table, one below the other, like the
    # status tables above.
    my $sect = sub {
        my ($title, $rows) = @_;
        my $h = $tbl_open . $hdr_row->($title);
        for my $r (@$rows) {
            my ($label, $val) = @$r;
            $h .= $row2->($label, $val);
        }
        return $h . $tbl_close . "<br>\n";
    };
    print $sect->('CS-AI Settings', \@general);
    print $sect->('Provider1', \@prov1);
    print $sect->('Provider2', \@prov2);
    print $sect->('Provider3 (Vision / Media Indexer)', \@prov3);
    print "<span style='color:#888;font-size:11px'>Save writes " . ai_esc(ai_cfg_path()) . "</span><br>\n";
    print "<input type='submit' value='Save'></form><br><br>\n";

    # ------------------------------------------- detailed field list (lang)
    # Field labels stay English (Basisregel); the explanatory texts come from
    # system.txt (ai_f_* keys), translated via get_language2.
    my @fields = (
        [ 'Provider',           'ai_f_provider' ],
        [ 'API key',            'ai_f_api_key' ],
        [ 'Model',              'ai_f_model' ],
        [ 'Provider 2',         'ai_f_provider2' ],
        [ 'API key 2',          'ai_f_api_key2' ],
        [ 'Model 2',            'ai_f_model2' ],
        [ 'Provider 3',         'ai_f_provider3' ],
        [ 'API key 3',          'ai_f_api_key3' ],
        [ 'Model 3',            'ai_f_model3' ],
        [ 'Daemon autostart',   'ai_f_autostart' ],
        [ 'Tool use (L1)',      'ai_f_tool_use' ],
        [ 'Exec access (L2)',   'ai_f_exec_access' ],
        [ 'Exec mode (L2)',     'ai_f_exec_mode' ],
        [ 'Exec allow (D2)',    'ai_f_exec_allow' ],
        [ 'Exec deny (always)', 'ai_f_exec_deny' ],
        [ 'History',            'ai_f_history' ],
        [ 'History turns',      'ai_f_history_turns' ],
        [ 'Widget (popup)',     'ai_f_widget' ],
        [ 'Popup input lines',  'ai_f_widget_input_lines' ],
        [ 'Popup answer height','ai_f_widget_answer_height' ],
        [ 'Web research',       'ai_f_research' ],
        [ 'Research results',   'ai_f_research_max' ],
        [ 'Logging',            'ai_f_log' ],
        [ 'SSRF private EP',    'ai_f_ssrf_allow_private' ],
        [ 'Rate limit (daemon)', 'ai_f_rate_limit' ],
        [ 'Context budget',     'ai_f_max_context' ],
    );
    print "<div style='max-width:780px'>\n";
    for my $pair (@fields) {
        my ($label, $key) = @$pair;
        my $t = ai_txt($key, '');
        next if $t eq '';
        print "<b>" . ai_esc($label) . "</b><br>\n";
        print $t . "<br><br>\n";
    }
    print "</div>\n";

    &log_end;
} #/ my_action

1;
