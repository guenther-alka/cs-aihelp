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
        $kv{widget}     = ai_trim($in{'cfg_widget'} // 'on');
        my $il = ai_trim($in{'cfg_widget_input_lines'} // '1');
        $kv{widget_input_lines} = ($il =~ /^\d+$/ && $il >= 1 && $il <= 10) ? $il : '1';
        my $ah = ai_trim($in{'cfg_widget_answer_height'} // '220');
        $kv{widget_answer_height} = ($ah =~ /^\d+$/ && $ah >= 100 && $ah <= 1200) ? $ah : '220';
        $kv{research}   = ai_trim($in{'cfg_research'} // 'ddg');
        my $rm = ai_trim($in{'cfg_research_max'} // '5');
        $kv{research_max} = ($rm =~ /^\d+$/ && $rm > 0) ? $rm : '5';
        $kv{research_endpoint} = ai_trim($in{'cfg_research_endpoint'} // '');
        $kv{research_key}      = ai_trim($in{'cfg_research_key'} // '');
        $kv{fallback}          = ai_trim($in{'cfg_fallback'} // 'free');
        $kv{log}               = ai_trim($in{'cfg_log'} // 'on');
        $kv{ssrf_allow_private}= ai_trim($in{'cfg_ssrf_allow_private'} // 'no');
        my $rl = ai_trim($in{'cfg_rate_limit'} // '60');
        $kv{rate_limit}        = ($rl =~ /^\d+$/ && $rl >= 0) ? $rl : '60';
        my $mc = ai_trim($in{'cfg_max_context'} // '');
        $kv{max_context} = ($mc =~ /^\d+$/ && $mc > 0) ? $mc : '8000';
        # keep existing keys if a password field was left empty
        $kv{api_key}  = $aicfg{api_key}  if $kv{api_key}  eq '';
        $kv{api_key2} = $aicfg{api_key2} if $kv{api_key2} eq '';

        my $ok = ai_cfg_write(%kv);
        print ($ok
            ? "<div style='color:#060;background:#dfd;border:1px solid #6a6;border-radius:4px;padding:6px 10px;display:inline-block'>"
                . ai_txt('ai_saved', 'AI Helpdesk settings saved.') . "</div>"
            : "<div style='color:#a00;background:#fee;border:1px solid #faa;border-radius:4px;padding:6px 10px;display:inline-block'>"
                . ai_txt('ai_save_failed', 'Error writing config file') . " " . ai_esc(ai_cfg_path()) . "</div>")
            . "<br><br>\n";
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
    my $st_rows  = "<b>Mode</b>\t$mode_html\n"
                 . "<b>Endpoint</b>\t$ep_html\n"
                 . "<b>Model</b>\t" . ($resolved ? ai_esc($resolved->{model} // '') : '') . "\n"
                 . "<b>Config</b>\t" . ai_esc(ai_cfg_path()) . "\n";
    print &list2table($st_rows, "160px,560px", "", "", "n");
    print "<br>";

    # --------------------------------------------------------------- form
    my $sel = sub {
        my ($name, $cur, @opts) = @_;
        my $h = "<select name='$name' style='width:200px'>";
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

    my $rows = "";
    # ---- slot 1: plan / read-only provider (default) ----
    $rows .= "<b>Mode</b>\t" . $sel->('cfg_mode', $aicfg{mode} // 'free', qw(off free provider))
        . $desc->("off = disabled | free = local Ollama, fallback Pollinations (no key) | provider = own endpoint + key") . "\n";
    $rows .= "<b>Provider</b>\t" . $sel->('cfg_provider', $aicfg{provider} // 'openai', qw(openai anthropic ollama))
        . $desc->("mode=provider only: openai / any OpenAI-compatible, anthropic, ollama (local)") . "\n";
    $rows .= "<b>Endpoint</b>\t<input type='text' name='cfg_endpoint' value=\"" . ai_esc($aicfg{endpoint} // '')
        . "\" style='width:340px' placeholder='empty = provider default'>"
        . $desc->("full chat-completions/messages URL; empty = provider default") . "\n";
    $rows .= "<b>Model</b>\t<input type='text' name='cfg_model' value=\"" . ai_esc($aicfg{model} // '')
        . "\" style='width:200px' placeholder='empty = provider default'>"
        . $desc->("e.g. gpt-4o-mini / claude-sonnet-5 / llama3.1") . "\n";
    # free mode: choose from the locally installed Ollama models
    my ($ollama_models, $ollama_reachable) = ai_ollama_models();
    my $fm_sel;
    if ($ollama_reachable && @$ollama_models) {
        $fm_sel = "<select name='cfg_free_model' style='width:240px'>";
        $fm_sel .= "<option value=''" . (($aicfg{free_model} // '') eq '' ? ' selected' : '') . ">auto (first available)</option>";
        for my $m (@$ollama_models) {
            $fm_sel .= "<option value='" . ai_esc($m) . "'" . (($aicfg{free_model} // '') eq $m ? ' selected' : '') . ">" . ai_esc($m) . "</option>";
        }
        $fm_sel .= "</select>";
    } else {
        $fm_sel = "<input type='text' name='cfg_free_model' value=\"" . ai_esc($aicfg{free_model} // '')
            . "\" style='width:200px' placeholder='auto'>";
    }
    $rows .= "<b>Free model</b>\t$fm_sel"
        . $desc->("mode=free: local Ollama model tag"
            . ($ollama_reachable
                ? " (" . scalar(@$ollama_models) . " installed, selection possible)"
                : " -- Ollama not reachable; 'auto' uses the first model once a daemon runs")) . "\n";
    $rows .= "<b>API key</b>\t<input type='password' name='cfg_api_key' value=\"\" style='width:280px' placeholder='cloud providers only'>"
        . $desc->(($aicfg{api_key} // '') ne ''
                  ? "key is set -- leave empty to keep; new key overwrites."
                  : "mode=free: not needed; enter for cloud providers") . "\n";

    # ---- slot 2: act/exec provider (Cline-style, optional) ----
    $rows .= "<tr><td colspan='2' style='padding-top:10px'><b>Slot 2 - act/exec provider</b> "
        . "<span style='color:#888;font-size:11px'>(optional; select in Helpdesk/popup; empty mode = uses slot 1)</span></td></tr>\n";
    my $m2sel = "<select name='cfg_mode2' style='width:200px'>"
        . "<option value=''" . (($aicfg{mode2} // '') eq '' ? ' selected' : '') . ">use slot 1</option>"
        . "<option value='free'" . (($aicfg{mode2} // '') eq 'free' ? ' selected' : '') . ">free</option>"
        . "<option value='provider'" . (($aicfg{mode2} // '') eq 'provider' ? ' selected' : '') . ">provider</option>"
        . "</select>";
    $rows .= "<b>Mode 2</b>\t$m2sel"
        . $desc->("empty = use slot 1 (plan provider) | free = free tier | provider = endpoint below") . "\n";
    $rows .= "<b>Provider 2</b>\t" . $sel->('cfg_provider2', $aicfg{provider2} // 'openai', qw(openai anthropic ollama))
        . $desc->("mode2=provider only") . "\n";
    $rows .= "<b>Endpoint 2</b>\t<input type='text' name='cfg_endpoint2' value=\"" . ai_esc($aicfg{endpoint2} // '')
        . "\" style='width:340px' placeholder='empty = provider default'>"
        . $desc->("full chat-completions/messages URL") . "\n";
    $rows .= "<b>Model 2</b>\t<input type='text' name='cfg_model2' value=\"" . ai_esc($aicfg{model2} // '')
        . "\" style='width:200px' placeholder='empty = provider default'>"
        . $desc->("e.g. gpt-4o-mini / claude-sonnet-5 / llama3.1") . "\n";
    $rows .= "<b>Free model 2</b>\t<input type='text' name='cfg_free_model2' value=\"" . ai_esc($aicfg{free_model2} // '')
        . "\" style='width:200px' placeholder='auto'>"
        . $desc->("mode2=free: local Ollama model tag") . "\n";
    $rows .= "<b>API key 2</b>\t<input type='password' name='cfg_api_key2' value=\"\" style='width:280px' placeholder='cloud providers only'>"
        . $desc->(($aicfg{api_key2} // '') ne ''
                  ? "key is set -- leave empty to keep."
                  : "cloud providers only") . "\n";
    $rows .= "<b>Tool use (L1)</b>\t" . $sel->('cfg_tool_use', $aicfg{tool_use} // 'no', qw(no yes))
        . $desc->("yes = AI gets read-only live state (hostname, zpool list) of the selected member as context") . "\n";
    $rows .= "<b>Exec access (L2)</b>\t" . $sel->('cfg_exec_access', $aicfg{exec_access} // 'ro', qw(ro exec console))
        . $desc->("ro (default) = read-only, no proposals/exec | exec = proposals, exec only from exec_allow (D2) | console = remote console (deny only) -- always with exec_mode confirm or auto") . "\n";
    $rows .= "<b>Exec mode (L2)</b>\t" . $sel->('cfg_exec_mode', $aicfg{exec_mode} // 'confirm', qw(propose confirm auto))
        . $desc->("propose = show only | confirm (recommended) = explicit click per command | auto = no per-step confirmation (tight allow list only)") . "\n";
    $rows .= "<b>Exec allow (D2)</b>\t<input type='text' name='cfg_exec_allow' value=\"" . ai_esc($aicfg{exec_allow} // '')
        . "\" style='width:340px' placeholder='e.g. zfs,zpool,find,curl,ls,grep'>"
        . $desc->("comma list of allowed command classes/prefixes (first word); empty = nothing executes. Examples: zfs, zfs snapshot, find, curl") . "\n";
    $rows .= "<b>Exec deny (always)</b>\t<input type='text' name='cfg_exec_deny' value=\"" . ai_esc($aicfg{exec_deny} // 'zfs destroy|zpool destroy|rm -rf|dd |mkfs|format')
        . "\" style='width:340px'>"
        . $desc->("always applied and wins against exec_allow; pipe-separated substrings") . "\n";
    $rows .= "<b>Daemon autostart</b>\t" . $sel->('cfg_autostart', $aicfg{autostart} // 'on', qw(on off))
        . $desc->("on = start the Go daemon at every server.pl boot (binary at data/cs_server/tools/cs-aihelp, mode != off); idempotent via 'cs-aihelp start'") . "\n";
    $rows .= "<b>History</b>\t" . $sel->('cfg_history', $aicfg{history} // 'month', qw(off today week month 6months all))
        . $desc->("one chat history per member; retention controls when old turns are deleted: off | today | week | month | 6months | all") . "\n";
    $rows .= "<b>History turns</b>\t<input type='text' name='cfg_history_turns' value=\"" . ai_esc($aicfg{history_turns} // '10')
        . "\" style='width:80px'>"
        . $desc->("how many prior turns are sent as context on resume") . "\n";
    $rows .= "<b>Widget (popup)</b>\t" . $sel->('cfg_widget', $aicfg{widget} // 'on', qw(on off))
        . $desc->("on = floating read-only 'Ask AI' popup on every logged-in page | off = helpdesk page only") . "\n";
    $rows .= "<b>Popup input lines</b>\t<input type='text' name='cfg_widget_input_lines' value=\"" . ai_esc($aicfg{widget_input_lines} // '1')
        . "\" style='width:80px'>"
        . $desc->("1 = single-line input | 2-10 = multiline textarea in the popup") . "\n";
    $rows .= "<b>Popup answer height (px)</b>\t<input type='text' name='cfg_widget_answer_height' value=\"" . ai_esc($aicfg{widget_answer_height} // '220')
        . "\" style='width:80px'>"
        . $desc->("height of the popup answer area in px (100-1200)") . "\n";
    $rows .= "<b>Web research</b>\t" . $sel->('cfg_research', $aicfg{research} // 'ddg', qw(off ddg api))
        . $desc->("off = local docs only | ddg (default) = DuckDuckGo Lite, no key | api = external search endpoint (+ optional key)") . "\n";
    $rows .= "<b>Research results</b>\t<input type='text' name='cfg_research_max' value=\"" . ai_esc($aicfg{research_max} // '5')
        . "\" style='width:80px'>"
        . $desc->("max. search results added to the context") . "\n";
    $rows .= "<b>Research endpoint</b>\t<input type='text' name='cfg_research_endpoint' value=\"" . ai_esc($aicfg{research_endpoint} // '')
        . "\" style='width:340px' placeholder='https://.../search?q={q}'>"
        . $desc->("research=api only: URL with {q} placeholder (Google CSE, Brave, Bing, SearXNG auto-detected); without {q} a ?q= is appended") . "\n";
    $rows .= "<b>Research key</b>\t<input type='password' name='cfg_research_key' value=\"\" style='width:280px' placeholder='optional'>"
        . $desc->(($aicfg{research_key} // '') ne ''
                  ? "research=api only; key is set -- leave empty to keep"
                  : "research=api only, if the service requires a key (Bearer/X-API-Key)") . "\n";
    $rows .= "<b>Fallback (setup)</b>\t" . $sel->('cfg_fallback', $aicfg{fallback} // 'free', qw(free off))
        . $desc->("if mode=provider fails: free = answer via the free tier (marked 'via free (Fallback)') | off = show an error") . "\n";
    $rows .= "<b>Logging</b>\t" . $sel->('cfg_log', $aicfg{log} // 'on', qw(on off))
        . $desc->("on = minimal metadata log (tmp/cs-aihelp.log, no question text) | off = no log") . "\n";
    $rows .= "<b>SSRF private EP</b>\t" . $sel->('cfg_ssrf_allow_private', $aicfg{ssrf_allow_private} // 'no', qw(no yes))
        . $desc->("yes = allow RFC1918/private endpoints for remote Ollama / local OpenAI-compatible servers -- trusted networks only; link-local/metadata stay blocked") . "\n";
    $rows .= "<b>Rate limit (daemon)</b>\t<input type='text' name='cfg_rate_limit' value=\"" . ai_esc($aicfg{rate_limit} // '60')
        . "\" style='width:80px'>"
        . $desc->("max. requests per minute per client IP in the Go daemon (0 = off)") . "\n";
    $rows .= "<b>Context budget</b>\t<input type='text' name='cfg_max_context' value=\"" . ai_esc($aicfg{max_context} // '8000')
        . "\" style='width:80px'>"
        . $desc->("max. characters of the system prompt (doc excerpts)") . "\n";

    print &list2table($rows, "180px,540px", "", "", "n");
    print "<br><span style='color:#888;font-size:11px'>Save writes " . ai_esc(ai_cfg_path()) . "</span><br>\n";
    print "<input type='submit' value='Save'></form><br><br>\n";

    # ------------------------------------------- translated info block (lang)
    my @info = (
        [ 'ai_intro',        'About' ],
        [ 'ai_provider_info', 'Provider' ],
        [ 'ai_exec_info',    'Command execution' ],
        [ 'ai_autostart_info','Daemon autostart' ],
        [ 'ai_history_info', 'Chat history' ],
        [ 'ai_popup_info',   'Popup' ],
        [ 'ai_privacy',      'Privacy' ],
    );
    print "<div style='max-width:780px'>\n";
    for my $pair (@info) {
        my ($key, $title) = @$pair;
        my $t = ai_txt($key, '');
        next if $t eq '';
        print "<b>" . ai_esc($title) . "</b><br>\n";
        print $t . "<br><br>\n";
    }
    print "</div>\n";

    &log_end;
} #/ my_action

1;
