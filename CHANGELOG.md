# Changelog

## dev (2026-08-24) - Helpdesk UI + i18n refinement (host-side)

**Per-question provider + mode choice, mini popup, translated field list.**

- **Settings form**: field hints minimized (one/two words, English); below the
  form a detailed per-field list via `$txt{'ai_f_*'}` from the new
  `lang/<lang>/system.txt` (all 7 languages). Slot label `Mode` -> `Mode 1`.
- **Helpdesk page**: independent per-question choice of **provider**
  (`mode1`/`mode2` = slot 1/2) and **mode** (`plan` = ro, `act` = exec) as two
  selects, plus Actions (propose/confirm/auto). Buttons `Ask`/`Abort`/`Resume`/
  `New`. `Enter` inserts a newline, sending happens only via `Ask`.
- **Popup**: title `mini AI Helpdesk`, `[x]` closes it, provider select
  `mode1`/`mode2` before `Ask`/`New`.
- **cs-aihelp.pl**: `action=load`/`resume` moved before the question guard
  (`load` was unreachable); new `action=resume` returns the newest saved
  conversation of the member (Resume button).
- **help.txt**: JS strings + quick questions now in all 7 languages; key set
  aligned (21 consumed keys) in every language.
- **Menu rename**: `System > CS Tools` -> **`System > CS Tools Download`**
  (m10.03, en+de; other languages use the English fallback). The page now
  offers a **local AI (Ollama)** section: status, platform download link
  (Linux/macOS/Windows only), a background **Pull model** form via the Ollama
  API (no shell, `ai_ollama_pull_bg`), plus a link to the AI Helpdesk
  settings. The cs-aihelp **daemon start/stop** moved from CS Tools to
  **System > Services > AI Helpdesk** (download/update stays in CS Tools
  Download, no more auto-start after download).

## v1.1 (2026-08-24) — pre-release / release candidate

**Published on GitHub as the newest downloadable release (marked as
pre-release / RC in the README) so it can be tested before the stable v1.1.0.
The stable path remains v1.0.2.**

- Same code as **v1.1rc2** (tag `v1.1rc2`, commit `01ca3b5`), released under
  the clean version tag `v1.1` — binaries report `1.1`, module archive
  `cs-aihelp-1.1.tar.gz`.
- Includes everything from v1.1.0 below, plus the CS Tools distribution
  extension and all commits on `main` since `v1.1rc`.

## v1.1.0 (2026-08-24)

**Two provider slots (Cline-style) + localised UI (Basisregel) + KISS history.**

- **`mode2` / `provider2` / `endpoint2` / `model2` / `api_key2` /
  `free_model2`** — a second provider slot for the **act/exec** model
  (slot 1 = plan/read-only). Empty `mode2` falls back to slot 1. The
  Helpdesk toolbar offers **Provider `Plan | Act` toggle buttons** (the
  popup a `plan|act` select + Ask) — `provider_use` in the request,
  answered as `provider_use` in the response; the Go daemon resolves the
  same way (`applyProviderSlot`).
- **Settings form** (under System > Services, m-key `m10.05.12`):
  English element labels + short English hints stay English (Basisregel);
  a detailed, translated **info section after the form** comes from the new
  language files `lang/{en,de}/ai_helpdesk.txt` (`ai_*` keys, ≤ 3 words).
- **Help page** (first item in the Help menu, `00_AI_Helpdesk`, m-key
  `m05.00`): English toolbar, quick questions / status / confirm / info
  texts translated via `lang/{en,de}/help.txt`, **Plan mode is the default**
  ("Plan first" checked), provider selector added.
- **Popup:** "Ask AI" (read-only), English labels, small Provider selector.
- **KISS history:** one chat history per member — the picker/`_aiLoadConv`
  is gone; `New` clears, `history` retention only deletes old turns.
- **Distribution via System > CS Tools:** all cs tools (cs-aihelp,
  cs-sleeper, cs-sync, cs-send, cs-stream, cs-freeze4snap) are **not
  bundled** in napp-it cs — the `10_System/03_CS_Tools` menu
  (`cstoolslib.pl` registry) lists tool / current version / newest version
  in a **100% width table** with a **download/update** link. Only the
  **frontend-OS** binary is fetched (tar archives `.tar.gz` and raw
  binaries are both supported) and installed keeping the **OS structure**
  (`data/cs_server/tools/<tool>/<platform>.<arch>/`), so
  `csweb-gui/data` can be copied to another OS. Newest versions are
  **cached for 1 h** (`_cfg/cstools_versions`, avoids GitHub rate limits).
  A second table manages the **local AI Helpdesk**: installed version,
  running/stopped, [Settings] link, **Start/Stop** and **Update**.
  The AI Helpdesk settings show *"please download CS tools first"* when
  the daemon is missing. v1.1rc was released as a **pre-release**.
- Tests: Perl 86/86, Go vet + unit green (slot tests in Perl #4b and
  `go/lifecycle_test.go`).

## v1.0.2 (2026-08-24)

**Level 2: exec + AI-Dialog (A3) + Status-Ampel AI dot.**

- **`exec_access = ro|exec|console`** (default `ro`): the AI's command
  scope. `ro` = read-only (no proposals, no execution). `exec` = proposals
  only from the D2 allow list. `console` = optional remote-console mode
  (only `exec_deny` applies).
- **`exec_mode = propose|confirm|auto`** (default `confirm`): `propose` =
  the AI may only show a command, never execute. `confirm` (recommended) =
  every exec needs a click on "Ausführen" in the browser. `auto` = the
  agentic loop runs without per-step confirmation.
- **`exec_allow` / `exec_deny`**: comma-separated allow list of command
  classes/prefixes (D2), pipe-separated deny list that ALWAYS wins
  (default `zfs destroy|zpool destroy|rm -rf|dd |mkfs|format`). An empty
  `exec_allow` means nothing may execute.
- **Execution happens in a new session-gated Perl CGI
  (`cgi-bin/cs-aihelp-exec.pl`)**, never in the Go daemon — the daemon is
  the proposer only. The CGI validates allow/deny and runs the command
  over the existing encrypted `&socket()`/`&exe()` channel.
- **A3 agentic loop (browser-orchestrated):** the daemon/Perl layer accept
  `tool_results`, extract a proposed `[[ACTION]]{...}[[/ACTION]]` block
  from the answer, return it as `action`, and feed the executed command's
  output back into the conversation — the AI can search pools, analyze
  and fix bugs step by step.
- **Full-screen AI Helpdesk (100% width/height):** toolbar (ro/exec/
  console radio, propose/confirm/auto select, optional "Plan zuerst"
  toggle, Abbrechen, Neu, Verlauf), 2:3 split — question on top, live
  transcript below with per-step 🧠 answer → 🔧 action card → ✅ output.
- **Popup:** read-only helper, freely draggable, size configurable via
  `widget_input_lines` and `widget_answer_height`.
- **Status-Ampel AI dot** (last dot, local read of `_cfg/cs-aihelp`):
  grey = disabled, green = read-only, blue = exec (click shows
  mode/exec_access/exec_mode/exec_allow).
- **Daemon lifecycle** — `cs-aihelp serve` writes a PID file
  (Unix `/var/run/cs-aihelp.pid`, Windows next to the config) and removes
  it on shutdown; new `cs-aihelp start` subcommand (detached, idempotent —
  skips when the listen port is already in use); `stop` is now
  cross-platform (`taskkill /PID … /F` on Windows instead of SIGINT).
- **`autostart = on|off`** (default `on`): `server_boot_tasks.pl` (server.pl
  boot hook) starts the Go daemon automatically at every server start when
  `mode != off` and the binary exists at
  `data/cs_server/tools/cs-aihelp[.exe]`; `install.pl` copies the binary
  there if it sits next to the installer.
- Tests: Perl 82/82, Go vet + unit green; new Level-2 unit tests
  (`exec_test.go`, Perl #24-29), `exec_e2e.ps1` and `lifecycle_smoke.ps1`
  (start/status/stop end-to-end).

## v1.0.1 (2026-08-24)

- **`ssrf_allow_private = no|yes`** (default `no`): allows RFC1918/private
  endpoints (LAN-only **remote Ollama** / local OpenAI-compatible servers);
  link-local, cloud-metadata and reserved ranges stay blocked. Makes the
  free tier usable on FreeBSD/illumos/Solaris via a remote Ollama host.
- **Ollama probe cache**: `/api/tags` reachability is cached for 30 s — no
  more 2 s latency per free question when Ollama is absent (falls through
  to Pollinations immediately).
- **Rate limit** (`rate_limit`, default 60): per-client-IP token bucket in
  the daemon (0 = off) — protects remote listeners from abuse.
- All three keys are editable in the settings menu and read by both the
  Go daemon and the Perl layer.

## v1.0.0 (2026-08-24)

**cs-aihelp is now an independent Go daemon** (`go/`), built for 8 platforms
(`CGO_ENABLED=0`), always ready in the background with its own memory
(in-memory RAG index, persisted chat history, reloadable config).

- CLI: `serve` (HTTPS daemon) · `ask` · `status` · `stop` · `reindex` · `version`.
- Endpoints: `GET /health /status /sources /models`, `POST /ask` (JSON/SSE),
  `POST /reload /reindex`.
- Remote reachable over HTTPS using the `webserver.pl` certificate
  (`_cfg/webserver/cert/server.crt`/`.key`).
- Security: IP allowlist (`allowed_ip`) + constant-time bearer token
  (`auth_token`), SSRF guard on configured endpoints, config files `0600`.
- All AI features ported from the Perl module: free/provider + fallback, RAG,
  web research (ddg/api), chat history, Level 1 read-only diagnostics.
- Security audit fixes (from the pre-implementation audit):
  - SSRF guard (provider + research endpoints),
  - `chmod 0600` on config/history,
  - no question text in logs (new `log` config key).
- Tests: Go unit tests (`go test ./...`) + Perl functional suite (49 checks).
- GitHub Actions: CI (Go vet+test, Perl tests) and Release (8-platform Go
  binaries + module archive + checksums).

## v0.5 (2026-08-24)

Initial public release of the **cs-aihelp** AI Helpdesk module for napp-it cs.

- Chat-based helpdesk inside the napp-it cs web-GUI (own menu `Help > AI
  Helpdesk`, plus a draggable context-sensitive popup on every page).
- Three modes (`_cfg/cs-aihelp`):
  - `free` (default): local Ollama auto-detect, falls back to a
    Pollinations.AI GET -- no account, no API key.
  - `provider`: Anthropic / OpenAI (or any OpenAI-compatible endpoint) /
    Ollama with optional API key.
  - `off`: disabled.
- Setup fallback: `fallback=free` (default) answers via the free tier when
  `mode=provider` fails (unreachable / wrong key), marked "via free (Fallback)".
- Light-RAG over `data/howto.ai/*.info` (napp-it knowledge base).
- Stufe 1: optional read-only live state (hostname, zpool list) as DATA context.
- Web research: `research=ddg` (DuckDuckGo Lite, no key, default) or
  `research=api` (any external JSON search endpoint, e.g. Google CSE, Brave,
  Bing, SearXNG, Serper -- response shape auto-detected).
- Chat history in `_cfg/aihelp/conv_*.json`, retention configurable
  (off | today | week | month | 6months | all, default month), resume via list.
- UX: quick questions, copy button, elapsed-time indicator, new conversation,
  friendly error texts, HTML-escaped answers.
- Stufe 2 (exec_mode propose/confirm/auto + allowlist) reserved, not implemented.
- Tests: `tests/ai_helpdesk_test.pl` against a local mock server (38 checks).
