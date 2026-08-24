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
        $kv{exec_mode}  = ai_trim($in{'cfg_exec_mode'} // 'off');
        $kv{tool_use}   = ai_trim($in{'cfg_tool_use'}  // 'no');
        $kv{history}    = ai_trim($in{'cfg_history'} // 'month');
        my $ht = ai_trim($in{'cfg_history_turns'} // '10');
        $kv{history_turns} = ($ht =~ /^\d+$/ && $ht > 0) ? $ht : '10';
        $kv{free_model} = ai_trim($in{'cfg_free_model'} // '');
        $kv{widget}     = ai_trim($in{'cfg_widget'} // 'on');
        $kv{research}   = ai_trim($in{'cfg_research'} // 'ddg');
        my $rm = ai_trim($in{'cfg_research_max'} // '5');
        $kv{research_max} = ($rm =~ /^\d+$/ && $rm > 0) ? $rm : '5';
        $kv{research_endpoint} = ai_trim($in{'cfg_research_endpoint'} // '');
        $kv{research_key}      = ai_trim($in{'cfg_research_key'} // '');
        $kv{fallback}          = ai_trim($in{'cfg_fallback'} // 'free');
        $kv{log}               = ai_trim($in{'cfg_log'} // 'on');
        my $mc = ai_trim($in{'cfg_max_context'} // '');
        $kv{max_context} = ($mc =~ /^\d+$/ && $mc > 0) ? $mc : '8000';
        # keep the existing key if the password field was left empty
        $kv{api_key} = $aicfg{api_key} if $kv{api_key} eq '';

        my $ok = ai_cfg_write(%kv);
        print ($ok
            ? "<div style='color:#060;background:#dfd;border:1px solid #6a6;border-radius:4px;padding:6px 10px;display:inline-block'>"
                . "AI Helpdesk Settings gespeichert.</div>"
            : "<div style='color:#a00;background:#fee;border:1px solid #faa;border-radius:4px;padding:6px 10px;display:inline-block'>"
                . "Fehler beim Schreiben von " . ai_esc(ai_cfg_path()) . "</div>")
            . "<br><br>\n";
        %aicfg = ai_cfg_read();
        print "<script>setTimeout(function(){ window.location.href=\"$base\"; }, 1500);</script>\n";
        &log_end;
        return;
    }

    # ------------------------------------------------------------ status
    my $mode_html = { off      => "<span style='color:#888'>off</span>",
                      free     => "<span style='color:darkgreen'><b>free</b></span> (sofort nutzbar, kein Key)",
                      provider => "<span style='color:#234'><b>provider</b></span>" }->{ $aicfg{mode} // 'off' }
                  // "<span style='color:#888'>" . ai_esc($aicfg{mode} // 'off') . "</span>";
    my $resolved = ai_resolve(%aicfg);
    my $ep_html  = $resolved ? "<span style='font-family:monospace;font-size:12px'>" . ai_esc($resolved->{endpoint} // '') . "</span>"
                            : '<i>kein Endpoint (off)</i>';
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
    $rows .= "<b>Mode</b>\t" . $sel->('cfg_mode', $aicfg{mode} // 'free', qw(off free provider))
        . $desc->("off = deaktiviert | <b>free</b> = automatisch: lokales Ollama (falls erreichbar, zuverlaessig+privat) sonst Pollinations.GE Fallback (sofort, experimentell, Rate-Limit) | provider = eigener Endpoint + Key") . "\n";
    $rows .= "<b>Provider</b>\t" . $sel->('cfg_provider', $aicfg{provider} // 'openai', qw(openai anthropic ollama))
        . $desc->("nur relevant bei mode=provider: openai (oder beliebiger OpenAI-kompatibler Dienst), anthropic, ollama (lokal)") . "\n";
    $rows .= "<b>Endpoint</b>\t<input type='text' name='cfg_endpoint' value=\"" . ai_esc($aicfg{endpoint} // '')
        . "\" style='width:340px' placeholder='leer = Provider-Default (z. B. https://api.openai.com/v1/chat/completions)'>"
        . $desc->("volle URL des chat-completions-/messages-Endpunkts; bei openai/anthropic/ollama leer lassen fuer Default") . "\n";
    $rows .= "<b>Model</b>\t<input type='text' name='cfg_model' value=\"" . ai_esc($aicfg{model} // '')
        . "\" style='width:200px' placeholder='leer = Provider-Default'>"
        . $desc->("nur mode=provider: z. B. openai / gpt-4o-mini / claude-sonnet-5 / llama3.1") . "\n";
    # free mode: choose from the locally installed Ollama models
    my ($ollama_models, $ollama_reachable) = ai_ollama_models();
    my $fm_sel;
    if ($ollama_reachable && @$ollama_models) {
        $fm_sel = "<select name='cfg_free_model' style='width:240px'>";
        $fm_sel .= "<option value=''" . (($aicfg{free_model} // '') eq '' ? ' selected' : '') . ">auto (erstes verfuegbares)</option>";
        for my $m (@$ollama_models) {
            $fm_sel .= "<option value='" . ai_esc($m) . "'" . (($aicfg{free_model} // '') eq $m ? ' selected' : '') . ">" . ai_esc($m) . "</option>";
        }
        $fm_sel .= "</select>";
    } else {
        $fm_sel = "<input type='text' name='cfg_free_model' value=\"" . ai_esc($aicfg{free_model} // '')
            . "\" style='width:200px' placeholder='auto'>";
    }
    $rows .= "<b>Free-Modell</b>\t$fm_sel"
        . $desc->("wirkt bei mode=free: lokales Ollama-Modell"
            . ($ollama_reachable
                ? " (" . scalar(@$ollama_models) . " installiert, Auswahl moeglich)"
                : " -- Ollama nicht erreichbar; 'auto' nutzt das erste Modell, sobald ein Daemon laeuft")) . "\n";
    $rows .= "<b>API-Key</b>\t<input type='password' name='cfg_api_key' value=\"\" style='width:280px' placeholder='nur Cloud-Provider'>"
        . $desc->(($aicfg{api_key} // '') ne ''
                  ? "Key ist gesetzt -- leer lassen, um ihn zu behalten; neuer Key ueberschreibt."
                  : "bei mode=free nicht noetig; bei Cloud-Providern hier eintragen") . "\n";
    $rows .= "<b>Tool-Use (Stufe 1)</b>\t" . $sel->('cfg_tool_use', $aicfg{tool_use} // 'no', qw(no yes))
        . $desc->("yes = KI bekommt read-only Systemzustand (hostname, zpool list) des gewaehlten Members als Kontext") . "\n";
    $rows .= "<b>Exec-Modus (Stufe 2)</b>\t" . $sel->('cfg_exec_mode', $aicfg{exec_mode} // 'off', qw(off propose confirm auto))
        . $desc->("reserviert: off = keine Aktionen | propose = nur Vorschlaege | confirm = Ausfuehrung nach Bestaetigung | auto = ohne Bestaetigung (nur mit Allowlist)") . "\n";
    $rows .= "<b>Verlauf (History)</b>\t" . $sel->('cfg_history', $aicfg{history} // 'month', qw(off today week month 6months all))
        . $desc->("Chatverlauf wird in _cfg/aihelp/conv_*.json gespeichert; Aufbewahrung: off = kein Verlauf | today = 24h | week = 7 Tage | month = 30 Tage | 6months = 180 Tage | all = unbegrenzt") . "\n";
    $rows .= "<b>Verlauf-Kontext</b>\t<input type='text' name='cfg_history_turns' value=\"" . ai_esc($aicfg{history_turns} // '10')
        . "\" style='width:80px'>"
        . $desc->("wie viele fruehere Runden beim Fortsetzen als Kontext mitgesendet werden") . "\n";
    $rows .= "<b>Widget (Popup)</b>\t" . $sel->('cfg_widget', $aicfg{widget} // 'on', qw(on off))
        . $desc->("on = schwebendes 'KI fragen'-Popup erscheint auf jeder eingeloggten Seite (im Hintergrund geladen) | off = nur im Chat-Menue") . "\n";
    $rows .= "<b>Recherche (Web)</b>\t" . $sel->('cfg_research', $aicfg{research} // 'ddg', qw(off ddg api))
        . $desc->("off = nur lokale Doku | <b>ddg</b> (Default) = DuckDuckGo Lite, kostenlos/kein Key, direkter Zugang | <b>api</b> = beliebiger externer Suchdienst ueber Endpoint (+ optional Key)") . "\n";
    $rows .= "<b>Recherche-Treffer</b>\t<input type='text' name='cfg_research_max' value=\"" . ai_esc($aicfg{research_max} // '5')
        . "\" style='width:80px'>"
        . $desc->("max. Anzahl Suchergebnisse, die in den Antwort-Kontext aufgenommen werden") . "\n";
    $rows .= "<b>API-Endpoint</b>\t<input type='text' name='cfg_research_endpoint' value=\"" . ai_esc($aicfg{research_endpoint} // '')
        . "\" style='width:340px' placeholder='https://.../search?q={q}'>"
        . $desc->("nur research=api: URL mit {q}-Platzhalter (z. B. Google CSE, Brave, Bing, SearXNG -- Antwort-Format wird automatisch erkannt); ohne {q} wird ?q= angehaengt") . "\n";
    $rows .= "<b>API-Key</b>\t<input type='password' name='cfg_research_key' value=\"\" style='width:280px' placeholder='optional'>"
        . $desc->(($aicfg{research_key} // '') ne ''
                  ? "nur research=api; Key ist gesetzt -- leer lassen, um ihn zu behalten"
                  : "nur research=api, falls der Dienst einen Key verlangt (als Bearer/X-API-Key gesendet)") . "\n";
    $rows .= "<b>Fallback (Setup)</b>\t" . $sel->('cfg_fallback', $aicfg{fallback} // 'free', qw(free off))
        . $desc->("falls mode=provider fehlschlaegt (nicht erreichbar/falscher Key): <b>free</b> = automatisch ueber die Free-Stufe antworten (Ollama lokal -> Pollinations), gekennzeichnet als 'via free (Fallback)' | off = Fehlermeldung anzeigen") . "\n";
    $rows .= "<b>Logging</b>\t" . $sel->('cfg_log', $aicfg{log} // 'on', qw(on off))
        . $desc->("on = minimales Metadaten-Log (tmp/cs-aihelp.log, <b>ohne</b> Fragetext) | off = kein Log (Datenschutz)") . "\n";
    $rows .= "<b>Kontext-Budget</b>\t<input type='text' name='cfg_max_context' value=\"" . ai_esc($aicfg{max_context} // '8000')
        . "\" style='width:80px'>"
        . $desc->("max. Zeichen des System-Prompts (Doku-Ausschnitte)") . "\n";

    print &list2table($rows, "180px,540px", "", "", "n");
    print "<br><span style='color:#888;font-size:11px'>Speichern schreibt " . ai_esc(ai_cfg_path()) . "</span><br>\n";
    print "<input type='submit' value='Save'></form><br><br>\n";

    # ------------------------------------------------- provider setup help
    print "<b>Provider-Setup Hilfe</b><br><br>\n";
    print "
<b>1. free (Default -- sofort nutzbar, kein Key)</b><br>
Nutzt automatisch das <b>lokale Ollama</b>, falls ein Daemon auf 127.0.0.1:11434
laeuft (zuverlaessig, privat, kostenlos). Sonst Fallback auf
<b>Pollinations.AI</b> (einfacher GET, keine Anmeldung, kein Key -- experimentell,
Rate-Limit, Fragen verlassen das Netz, keine SLA). Fuer zuverlaessigen
Free-Betrieb einfach Ollama installieren:<br>
<span style='font-family:monospace'>curl -fsSL https://ollama.com/install.sh | sh</span>
bzw. Windows-Installer von ollama.com, dann <span style='font-family:monospace'>ollama pull llama3.1</span>.<br><br>
<b>2. provider -- ollama (lokal, kostenlos, kein Key, beste Privatsphaere)</b><br>
Wie oben installieren, dann Provider = ollama, Endpoint = <span style='font-family:monospace'>http://127.0.0.1:11434/api/chat</span>, Model = llama3.1.<br><br>
<b>3. provider -- anthropic (beste Qualitaet)</b><br>
Key unter <span style='font-family:monospace'>https://console.anthropic.com</span>.
Provider = anthropic, Model = claude-sonnet-5.<br><br>
<b>4. provider -- openai / OpenAI-kompatibel</b><br>
Key unter <span style='font-family:monospace'>https://platform.openai.com</span>.
Provider = openai, Model = gpt-4o-mini. Fuer jeden OpenAI-kompatiblen Dienst
(vLLM, LM Studio, Groq, ...) die volle chat-completions-URL als Endpoint eintragen.<br><br>
<b>Hinweis Datenschutz:</b> Pollinations und Cloud-Provider senden die Frage (inkl.
Tool-Use-Kontext) an einen externen Dienst. Fuer sensible Umgebungen Ollama lokal verwenden.
";
    print "<br>";

    &log_end;
} #/ my_action

1;
