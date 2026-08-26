# cs-aihelp — AI Helpdesk for napp-it cs

A chat-based **AI helpdesk** that runs directly inside the
[napp-it cs](https://napp-it.org) web-GUI. It answers napp-it questions
grounded in the local documentation (`data/howto.ai/*.info`, light-RAG),
optionally enriches the answer with a web search, and can be wired to a
local or cloud LLM — with or without an API key.

> **Version:** v1.2.2 (stable) · **License:** BSD 2-Clause · **Platform:** frontend on
> any napp-it cs OS (FreeBSD, illumos, Linux, macOS, Solaris, Windows); the Go
> daemon is built for 8 targets (mswin/linux/illumos/solaris/freebsd/darwin).
> Local free AI (Ollama) runs natively on **Linux/macOS/Windows**; on
> FreeBSD/illumos/Solaris use the Pollinations fallback, a remote Ollama
> (`OLLAMA_BASE` / `provider=ollama` + endpoint) or an OpenAI-compatible
> local server (e.g. llama.cpp).

> **v1.2.2 is the current stable release** on GitHub — the pre-release/
> release-candidate phase (v1.1.x) ended with v1.2.0. See
> [CHANGELOG.md](CHANGELOG.md) for the full version history.

---

## Table of contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Configuration](#configuration)
  - [Config keys](#config-keys)
  - [Provider setup](#provider-setup)
  - [Web research](#web-research)
  - [Chat history](#chat-history)
- [Usage](#usage)
  - [Chat menu](#chat-menu)
  - [Floating popup](#floating-popup)
- [Security model](#security-model)
- [Architecture](#architecture)
- [Testing](#testing)
- [Building / releasing](#building--releasing)
- [License](#license)

---

## Features

- **Zero-config free tier** — `mode=free` works out of the box without an
  account or API key: it prefers a local **Ollama** daemon and falls back to a
  **Pollinations.AI** GET.
- **Bring-your-own provider** — `mode=provider` for **Anthropic**, **OpenAI**
  (or any OpenAI-compatible endpoint: vLLM, LM Studio, Groq, ...) and
  **Ollama** (no key needed).
- **No silent fallback** — a failing `mode=provider` call (unreachable,
  wrong key, timeout) is surfaced as an error, not quietly answered by a
  different, uncontrolled model. (Removed in v1.2 — earlier versions had an
  automatic `fallback=free` retry via the local/free tier; the `fallback`
  config key is still parsed for backward compatibility but no longer acted
  on.)
- **Grounded answers, sourced transparently** — light-RAG over
  `data/howto.ai/*.info`, with filename-aware relevance ranking so a
  question naming a topic (e.g. "what is cs-sync") reliably surfaces the
  matching doc instead of losing out to generic ones. Every answer is
  structured into two labeled sections — **"Local docs:"** (strictly
  grounded in the retrieved excerpts, never invents napp-it-specific
  commands/paths/settings) and **"General AI:"** (the model's own
  background knowledge, always included) — so it's always clear where
  each part of the answer came from.
- **Level 1 read-only diagnostics** — optionally attach live state
  (`hostname`, `zpool list`) of the selected member as DATA context.
- **Level 2 exec (agentic)** — with `exec_access = exec|console` the AI may
  *propose* commands; execution is gated by a D2 allow list (`exec_allow`)
  and a deny list that always wins (`exec_deny`), runs **only** after your
  confirmation (`exec_mode=confirm`, default) in a dedicated session-gated
  CGI, and its output is fed back into the conversation — the AI can search
  pools, analyze and fix bugs step by step. See *Security model*.
- **Web research** — `research=ddg` (DuckDuckGo Lite, no key, default) or
  `research=api` (any external JSON search endpoint; Google CSE, Brave, Bing,
  SearXNG and Serper response shapes are auto-detected). Result URLs are shown
  in the sources line.
- **Chat history** — conversations stored per file in
  `_cfg/aihelp/conv_*.json`, retention configurable
  (`off | today | week | month | 6months | all`, default `month`), resume any
  earlier conversation from the history list. The current conversation is
  also auto-loaded on render (per widget/full-screen, via a client-side
  cookie) until **New** starts a fresh one -- no manual Resume click
  needed for the common case of just continuing where you left off.
- **Two UIs** — a full chat page (`Help > AI Helpdesk`, first item in the
  Help menu) and a draggable, context-sensitive **popup** ("Ask AI")
  injected on every logged-in page (`widget=on`).
- **Two provider slots (Cline-style)** — slot 1 = plan/read-only provider,
  slot 2 = act/exec provider; select `plan` or `act` in the Helpdesk/popup
  menu. Empty `mode2` falls back to slot 1.
- **Localised UI** — settings form elements and short hints stay English;
  the explanations/info/confirm texts after the form and in the Helpdesk/
  popup are translated via the napp-it language files
  (`lang/*/ai_helpdesk.txt`, `lang/*/help.txt`, menu keys `m05.00`/`m12`).
- **Nice UX** — quick questions, copy button, elapsed-time indicator, new
  conversation, friendly error texts, mode badge; answers are HTML-escaped.
  Plan mode ("Plan first") is the default in the Help screen; one chat
  history per member (`history` = retention only).

---

## Go daemon (v1.0) — independent background service

Since v1.0, cs-aihelp ships as a **standalone Go daemon** (`go/`, pure
standard library, `CGO_ENABLED=0`, built for 8 platforms) with its **own
memory**: an in-memory RAG index over `data/howto.ai/*.info`, persisted chat
history (`_cfg/aihelp/conv_*.json`, same format as the Perl frontend) and a
reloadable in-memory config. It is **always ready in the background** and
reachable remotely over HTTPS.

```
cs-aihelp serve   [--listen 0.0.0.0:45555] [--config PATH] [--foreground]
cs-aihelp start   [--config PATH]   (detached + idempotent; boot hook)
cs-aihelp ask     --question "..." [--json]
cs-aihelp status  [--json]
cs-aihelp stop    [--config PATH]   (reads the daemon PID file)
cs-aihelp reindex
cs-aihelp version
```

`serve` writes a PID file (Unix `/var/run/cs-aihelp.pid`, Windows next to
the config) and removes it on shutdown; `start` is the boot-hook entry point
(detached, skips when the port is already in use); `stop` works on all
platforms (`taskkill` on Windows).

Endpoints (HTTPS, Bearer auth): `GET /health /status /sources?q= /models`
and `GET /resume?member=...` (newest conversation of the member),
`POST /ask` (JSON or `stream=true` → SSE), `POST /reload /reindex`. From the
browser these are reached via the session-gated `cs-aihelp.pl` proxy.

Daemon-only config keys (in the same `_cfg/cs-aihelp`):

| Key | Description |
|---|---|
| `listen` | `127.0.0.1:45555` (default) · `0.0.0.0:45555` for remote |
| `allowed_ip` | comma-separated IP/CIDR allowlist; empty = loopback only; `*` = any |
| `auth_token` | bearer token (mandatory when `listen` is not loopback) |
| `tls_cert` / `tls_key` | default = the `webserver.pl` certificate (`_cfg/webserver/cert/server.crt`/`.key`) |
| `cors_origin` | frontend origin for CORS pinning (optional) |
| `ssrf_allow_private` | `no` \| `yes` — allow RFC1918/private endpoints (LAN-only remote Ollama); metadata/link-local stay blocked |
| `rate_limit` | max requests/min per client IP in the daemon (0 = off, default 60) |

Security: IP allowlist + constant-time bearer-token check, SSRF guard on all
configured endpoints, TLS with the same certificate the web-GUI uses (so
remote browsers already trust it), config files written `0600`.

**Deploy:** `data/cs_server/tools/cs-aihelp/<os>.<arch>/cs-aihelp[.exe]`,
started by `autostart.pl` alongside `server.pl`/`auto.pl`/`monitor.pl`.

---

## Requirements

- An installed **napp-it cs** web-GUI (default path `/opt/csweb-gui`;
  on Windows `C:\opt\csweb-gui`).
- **Perl** with core modules (`HTTP::Tiny`, `JSON::PP`) plus
  **`URI::Escape`** (`liburi-perl` on Debian/Ubuntu; already bundled with
  napp-it cs at `data/cs_server/CGI`).
- Optional, for the free tier:
  - **Ollama** — `curl -fsSL https://ollama.com/install.sh | sh` (or the
    Windows installer from [ollama.com](https://ollama.com)), then
    `ollama pull llama3.1`. Free mode auto-detects it on `127.0.0.1:11434`.
  - Internet access, if you want the Pollinations fallback or web research.
- Optional, for cloud providers: an API key from
  [console.anthropic.com](https://console.anthropic.com) or
  [platform.openai.com](https://platform.openai.com).

---

## Installation

Copy the module files into the napp-it cs installation:

```sh
# from this repository
perl install.pl /opt/csweb-gui     # default target is /opt/csweb-gui
```

`install.pl` copies:

| File | Install target |
|---|---|
| `data/wwwroot/cgi-bin/cs-aihelp.pl` | session-gated proxy → Go daemon (chat, SSE) |
| `data/wwwroot/cgi-bin/cs-aihelp-exec.pl` | exec CGI (Level 2) |
| `data/menues/_lib/windows/aihelplib.pl` | shared library |
| `data/menues/_lib/windows/cstoolslib.pl` | CS tools registry + GitHub download |
| `data/menues/05_Help/00_AI_Helpdesk/action.pl` | chat menu (first item in Help) |
| `data/menues/10_System/05_Services/12_AI_Helpdesk/action.pl` | settings menu |
| `data/menues/_lib/tools/CS_Tools_Download/action.pl` | **System > CS Tools Download** download/update menu (incl. local AI / Ollama) |
| `data/howto.ai/ai-helpdesk.info` | module documentation |
| `config/cs-aihelp.example` → `_cfg/cs-aihelp` | default config (only if absent) |

**cs-aihelp is not bundled in napp-it cs.** The Go daemon binary is
downloaded from GitHub via **System > CS Tools Download** ("download/update") — on
first use the settings menu shows *"please download CS tools first"*. The
newest release on GitHub is fetched (currently **v1.2.2**, stable). Only
the binary for the **frontend OS** is fetched; it is installed keeping the
**OS structure** (`data/cs_server/tools/cs-aihelp/<platform>.<arch>/`), so
`csweb-gui/data` can be copied to another OS — there the matching binary is
resolved (and fetched in CS Tools Download if missing). The same page offers
**local AI (Ollama)** download/setup (Linux/macOS/Windows) and a background
model pull; the daemon start/stop lives in **System > Services > AI Helpdesk**.

Alternatively, copy the files manually into the same paths. **No restart is
needed** for the menus (napp-it cs scans menu folders per request); the config
file is read on every request.

---

## Quick start

1. Install the module (`perl install.pl`).
2. Reload the web-GUI and log in.
3. **Install Ollama** for a reliable free setup:
   ```sh
   curl -fsSL https://ollama.com/install.sh | sh
   ollama pull llama3.1
   ```
4. Open **Help > AI Helpdesk** and ask a question. It works immediately in
   `mode=free` (Ollama, or Pollinations fallback if Ollama is not installed).
5. Optional: **System > Services > AI Helpdesk** to choose a free model, a
   cloud provider, web research and other options.

---

## Configuration

The module is configured in **System > Services > AI Helpdesk** (
previously System > Services) — saved to `_cfg/cs-aihelp`, a flat
`key = value` file, auto-created on first run.

### Config keys

| Key | Values (default) | Description |
|---|---|---|
| `mode` | `off` \| `free` \| `provider` (`free`) | slot 1 (plan/RO): `free` = no key, local Ollama → Pollinations; `provider` = configured endpoint + optional key |
| `provider` | `openai` \| `anthropic` \| `ollama` (`openai`) | slot 1, used in `mode=provider` |
| `endpoint` | URL (empty) | slot 1: full chat-completions/messages URL; empty = provider default |
| `model` | string (empty) | slot 1: empty = provider default (`openai`, `claude-sonnet-5`, `llama3.1`) |
| `api_key` | string (empty) | slot 1: cloud providers only; stored server-side, never logged |
| `mode2` | `''` \| `free` \| `provider` (`''`) | slot 2 (act/exec provider, Cline-style); **empty/off = uses slot 1** |
| `provider2` | `openai` \| `anthropic` \| `ollama` (`openai`) | slot 2, used in `mode2=provider` |
| `endpoint2` / `model2` / `api_key2` / `free_model2` | (empty) | slot 2 provider settings |
| `free_model` | string (empty) | slot 1 `mode=free`: local Ollama model tag; empty = first available |
| `fallback` | `off` (`off`) | removed in v1.2 (was: answer via free tier when `mode=provider` fails) — parsed for backward compat only, no longer acted on |
| `tool_use` | `no` \| `yes` (`no`) | Level 1: attach read-only live state (hostname, zpool list) |
| `research` | `off` \| `ddg` \| `api` (`ddg`) | web research; `ddg` = DuckDuckGo Lite (no key), `api` = external endpoint |
| `research_max` | number (`5`) | max. search results added to the context |
| `research_endpoint` | URL (empty) | `research=api`: URL template with `{q}` (or auto `?q=`) |
| `research_key` | string (empty) | `research=api`: optional key (sent as Bearer / X-API-Key) |
| `history` | `off`\|`today`\|`week`\|`month`\|`6months`\|`all` (`month`) | chat history retention |
| `history_turns` | number (`10`) | prior turns sent as context on resume |
| `widget` | `on` \| `off` (`on`) | floating **read-only** "Ask AI" popup on every logged-in page |
| `widget_input_lines` | number (`1`) | popup question field: 1 = single line, 2-10 = multiline textarea |
| `widget_answer_height` | number (`220`) | popup answer area height in px (100-1200) |
| `exec_access` | `ro` \| `exec` \| `console` (`ro`) | Level 2: `ro` = read-only (no proposals/exec), `exec` = D2 allow list, `console` = only `exec_deny` applies |
| `exec_mode` | `propose` \| `confirm` \| `auto` (`confirm`) | Level 2: `propose` = show only, `confirm` = every exec needs a click, `auto` = no per-step confirmation |
| `exec_allow` | comma list (empty) | D2 command classes/prefixes that may execute (first word of the command chain); **empty = nothing executes** |
| `exec_deny` | pipe list | always applied, wins against `exec_allow`; default `zfs destroy|zpool destroy|rm -rf|dd |mkfs|format` |
| `autostart` | `on` \| `off` (`on`) | start the Go daemon at every server.pl boot (when `mode != off` and `data/cs_server/tools/cs-aihelp` exists) |
| `max_context` | number (`8000`) | system-prompt budget in characters |

### Provider setup

| Option | What it is | Key needed |
|---|---|---|
| `free` | Local **Ollama** (reliable, private) with **Pollinations.AI** GET fallback (instant, experimental) | no |
| `provider = ollama` | Local Ollama via explicit provider config | no |
| `provider = anthropic` | Claude (best quality) | yes (`console.anthropic.com`) |
| `provider = openai` | OpenAI or any OpenAI-compatible service | yes (or none for local servers) |

**Privacy:** `free` (Pollinations) and cloud providers send the question
(including tool-use context) to an external service. Use `ollama` locally for
sensitive environments.

### Web research

- `research=ddg` (default) uses `lite.duckduckgo.com` — free, no key, direct
  internet access. Note: direct **Google** scraping is blocked by Google
  (consent/JS page), so for Google use `research=api` with a Google CSE key.
- `research=api` calls any JSON search endpoint:
  `research_endpoint = https://www.googleapis.com/customsearch/v1?key=…&cx=…&q={q}`
  (the `{q}` placeholder is replaced with the question; if absent, `?q=` is
  appended). Response shapes for Google CSE, Brave, Bing, SearXNG and Serper
  are auto-detected.

### Chat history

Conversations are stored in `_cfg/aihelp/conv_<timestamp>_<id>.json`
(`{created, updated, member, title, messages[]}`). Only question/answer pairs
are stored — never system prompts or secrets. Cleanup runs lazily on each
request according to `history`. On resume, the last `history_turns` turns are
sent to the model as context.

---

## Usage

### Chat menu

**Help > AI Helpdesk** opens the full-screen chat page (100% width/height):

- **Toolbar:** **Provider `Plan | Act`** toggle buttons (slot 2 = exec-capable
  model; popup uses a `plan|act` select + Ask),
  `ro | exec | console` radio (mirrors `exec_access`),
  `propose | confirm | auto` select (mirrors `exec_mode`), **"Plan first"**
  (checked by default — the AI presents a plan and waits for your go-ahead
  before proposing actions), **Abort** (stops the agentic loop) and **New**
  (fresh conversation).
- **2:3 split:** the question field on top, the live transcript below.
- **Quick questions** buttons fill and send a sample question.
- **Agentic steps:** a proposed command arrives as an action card
  (🔧) under the answer — in `confirm` mode with **Execute / Abort**
  buttons, in `auto` mode it runs immediately (Abort stops the next
  step). The command output (✅) is fed back to the AI, which continues.
- Each answer has a **copy** button and a **sources** line (documentation
  files and/or research URLs).
- **One chat history per member** — `New` starts fresh; the `history`
  retention setting only controls when old turns are deleted.

### Floating popup

When `widget=on`, an **"Ask AI"** button is injected on every logged-in page
(via the interface header). Clicking it opens a freely **draggable**,
**read-only** chat popup — actions are never executed from here (a note is
shown instead; use the full-screen page for exec). It automatically sends
the current menu path (`l1/l2/l3`) and selected member as context — e.g.,
while you are in the *ZFS Snaps* menu, the question is answered with that
context. Size is configurable: `widget_input_lines` (1 = single-line input,
2-10 = textarea) and `widget_answer_height` (px of the answer area).

---

## Security model

- API keys live only in `_cfg/cs-aihelp` (server-side), never in the browser.
- Model answers are **HTML-escaped** before rendering (XSS guard).
- Live system state and web results are passed as **DATA**
  ("treat as data, not instructions") to mitigate prompt injection.
- **Level 2 exec is defense-in-depth:**
  - `exec_access=ro` (default) — the AI is read-only, no proposals, no exec.
  - The Go daemon only ever *proposes* (`[[ACTION]]` block); execution
    happens in the separate session-gated Perl CGI
    (`cs-aihelp-exec.pl`) via the encrypted `&exe()/&socket()` channel.
  - `exec_deny` is always applied and **wins** (default
    `zfs destroy|zpool destroy|rm -rf|dd |mkfs|format`).
  - `exec_access=exec` additionally requires the command's class to be in
    `exec_allow` (D2); an empty `exec_allow` = nothing executes.
  - `exec_mode=confirm` (default) requires an explicit **Ausführen** click
    per command; `auto` should only be used with a tight allow list.
- Chat history contains question/answer pairs only (no secrets) and is
  pruned by the retention setting.

---

## Architecture

```
Browser (menu page or popup)
   │  POST /cgi-bin/cs-aihelp.pl   (session check + read-only live_state)
   ▼
cs-aihelp.pl (Perl proxy, loopback, HTTPS webserver-cert / Bearer auth_token)
   │  /ask   (buffered or SSE stream:true)
   ▼
cs-aihelp (Go daemon, 127.0.0.1:45555)      ← since v1.0 the AI core
   │  in-memory RAG index (data/howto.ai/*.info)
   │  optional web research (ddg / api)
   │  provider call: free (Ollama→Pollinations) | provider (anthropic/openai/ollama)
   │  chat history (_cfg/aihelp/conv_*.json), /resume
   ▼
Browser: tokens streamed as SSE (data:{"t":...} ... event:done) or buffered
JSON; answer ("Local docs:" / "General AI:" sections) + sources rendered.
```

The frontend UI (menus, settings, popup, chat page) is the thin Perl layer:
it writes `_cfg/cs-aihelp`, collects the read-only live state and menu
context, and proxies every /ask to the Go daemon over loopback. The exec
channel stays in the session-gated Perl CGI (`cs-aihelp-exec.pl`).

**Level 2 agentic loop (A3, browser-orchestrated):** the browser runs the
loop, the daemon only answers.

```
Browser (full-screen chat page)
   │  1. question (via cs-aihelp.pl proxy)
   ▼
daemon /ask ──▶ answer (+ optional [[ACTION]]{cmd,reason})  [SSE stream]
   │
   │  action shown: confirm mode → user clicks "Ausführen",
   │                auto mode → runs automatically
   ▼
cgi-bin/cs-aihelp-exec.pl   (session-gated, D2 allow/deny validation)
   │  executes over the encrypted &exe()/&socket() channel
   ▼
Browser ── tool_results (command output) ──▶ daemon /ask via proxy (continues)
```

Execution never happens in the Go daemon — it is proposer only.

### csweb-gui patches (Status-Ampel dot + popup injection + daemon autostart + i18n)

Four UI/boot hooks touch core napp-it files and are applied on the napp-it
side (they are **not** part of `install.pl`'s module file list):

- **Status-Ampel AI dot** — `get_async.pl` (`_h_sys_ample`, last dot) and
  `admin-wlib.pl` (skeleton `<img id='ample_ai'>`, labels, popup renderer).
- **Popup injection** — `interface.pl` header calls `ai_popup(...)` when
  `widget=on`; `admin.pl` (per-session config availability).
- **Daemon autostart** — `server_boot_tasks.pl` calls
  `ai_boot_autostart()` at every server.pl start (gate: `mode != off`,
  `autostart=on`, binary present).
- **Localisation** — new language files `lang/{en,de,...}/ai_helpdesk.txt`
  and `lang/{en,de,...}/help.txt` plus the two AI Helpdesk menu keys
  (`m05.00`, `m12`) in `about_menus.txt`.

These patches ship with the csweb-gui tree; applying the module itself only
copies the files listed in `install.pl`.

---

## Testing

```sh
# Linux / macOS / illumos:
tests/run_tests.sh

# Windows:
powershell -ExecutionPolicy Bypass -File tests/run_tests.ps1
```

The Perl suite starts a local mock HTTP server (OpenAI-compatible chat, Ollama
`/api/tags`+`/api/chat`, DuckDuckGo-Lite HTML, Google-CSE JSON) and runs
**49 functional checks**: config read/write/roundtrip, provider resolve,
RAG retrieval, history save/load/list/cleanup, provider call + error paths,
free-tier Ollama path, DDG research parsing, external API research mapping,
setup fallback, SSRF guard, and the `log` key. The Go daemon has its own
unit tests (`go test ./...`) covering config, SSRF, RAG, providers (via
httptest) and research mapping. Requires `URI::Escape` on the test host.

---

## Building / releasing

GitHub Actions builds the release on a `v*` tag:

- `.github/workflows/ci.yml` — Go `vet`+`test` and the Perl suite on every
  push / PR.
- `.github/workflows/release.yml` — builds the **Go daemon for 8 platforms**
  (`cs-aihelp-<os>.<arch>.tar.gz`, `CGO_ENABLED=0`) plus the **module archive**
  (`cs-aihelp-<version>.tar.gz`), writes `checksums.txt` and publishes the
  GitHub Release.

```sh
git tag v1.0.0
git push origin v1.0.0
```

---

## License

BSD 2-Clause. Copyright (c) 2026 Guenther Alka / napp-it.org.

