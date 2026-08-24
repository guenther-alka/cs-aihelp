# cs-aihelp — AI Helpdesk for napp-it cs

A chat-based **AI helpdesk** that runs directly inside the
[napp-it cs](https://napp-it.org) web-GUI. It answers napp-it questions
grounded in the local documentation (`data/howto.ai/*.info`, light-RAG),
optionally enriches the answer with a web search, and can be wired to a
local or cloud LLM — with or without an API key.

> **Version:** v1.0.0 · **License:** BSD 2-Clause · **Platform:** frontend on
> any napp-it cs OS (FreeBSD, illumos, Linux, macOS, Solaris, Windows); the Go
> daemon is built for 8 targets (mswin/linux/illumos/solaris/freebsd/darwin).
> Local free AI (Ollama) runs natively on **Linux/macOS/Windows**; on
> FreeBSD/illumos/Solaris use the Pollinations fallback, a remote Ollama
> (`OLLAMA_BASE` / `provider=ollama` + endpoint) or an OpenAI-compatible
> local server (e.g. llama.cpp).

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
- **Setup fallback** — `fallback=free` (default): if the configured provider
  fails (unreachable, wrong key, timeout), the helpdesk automatically answers
  via the free tier and marks the answer *"via free (fallback)"*.
- **Grounded answers** — light-RAG over `data/howto.ai/*.info`; unknown
  questions are answered from the documentation instead of hallucinated.
- **Level 1 read-only diagnostics** — optionally attach live state
  (`hostname`, `zpool list`) of the selected member as DATA context.
- **Web research** — `research=ddg` (DuckDuckGo Lite, no key, default) or
  `research=api` (any external JSON search endpoint; Google CSE, Brave, Bing,
  SearXNG and Serper response shapes are auto-detected). Result URLs are shown
  in the sources line.
- **Chat history** — conversations stored per file in
  `_cfg/aihelp/conv_*.json`, retention configurable
  (`off | today | week | month | 6months | all`, default `month`), resume any
  earlier conversation from the history list.
- **Two UIs** — a full chat page (`Help > AI Helpdesk`) and a draggable,
  context-sensitive **popup** ("Ask AI") injected on every logged-in page
  (`widget=on`).
- **Nice UX** — quick questions, copy button, elapsed-time indicator, new
  conversation, friendly error texts, mode badge; answers are HTML-escaped.

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
cs-aihelp ask     --question "..." [--json]
cs-aihelp status  [--json]
cs-aihelp stop
cs-aihelp reindex
cs-aihelp version
```

Endpoints (HTTPS, Bearer auth): `GET /health /status /sources?q= /models`,
`POST /ask` (JSON or `stream=true` → SSE), `POST /reload /reindex`.

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
| `data/wwwroot/cgi-bin/cs-aihelp.pl` | JSON CGI (chat backend) |
| `data/menues/_lib/windows/aihelplib.pl` | shared library |
| `data/menues/05_Help/50_AI_Helpdesk/action.pl` | chat menu |
| `data/menues/10_System/05_Services/70_AI_Helpdesk/action.pl` | settings menu |
| `data/howto.ai/ai-helpdesk.info` | module documentation |
| `config/cs-aihelp.example` → `_cfg/cs-aihelp` | default config (only if absent) |

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

The module is configured in **System > Services > AI Helpdesk** (saved to
`_cfg/cs-aihelp`, a flat `key = value` file, auto-created on first run).

### Config keys

| Key | Values (default) | Description |
|---|---|---|
| `mode` | `off` \| `free` \| `provider` (`free`) | `free` = no key, local Ollama → Pollinations; `provider` = configured endpoint + optional key |
| `provider` | `openai` \| `anthropic` \| `ollama` (`openai`) | used in `mode=provider` |
| `endpoint` | URL (empty) | full chat-completions/messages URL; empty = provider default |
| `model` | string (empty) | empty = provider default (`openai`, `claude-sonnet-5`, `llama3.1`) |
| `api_key` | string (empty) | cloud providers only; stored server-side, never logged |
| `free_model` | string (empty) | `mode=free`: local Ollama model tag; empty = first available |
| `fallback` | `off` \| `free` (`free`) | answer via free tier when `mode=provider` fails |
| `tool_use` | `no` \| `yes` (`no`) | Level 1: attach read-only live state (hostname, zpool list) |
| `research` | `off` \| `ddg` \| `api` (`ddg`) | web research; `ddg` = DuckDuckGo Lite (no key), `api` = external endpoint |
| `research_max` | number (`5`) | max. search results added to the context |
| `research_endpoint` | URL (empty) | `research=api`: URL template with `{q}` (or auto `?q=`) |
| `research_key` | string (empty) | `research=api`: optional key (sent as Bearer / X-API-Key) |
| `history` | `off`\|`today`\|`week`\|`month`\|`6months`\|`all` (`month`) | chat history retention |
| `history_turns` | number (`10`) | prior turns sent as context on resume |
| `widget` | `on` \| `off` (`on`) | floating "Ask AI" popup on every logged-in page |
| `exec_mode` | `off`\|`propose`\|`confirm`\|`auto` (`off`) | Level 2, **reserved — not implemented yet** |
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

**Help > AI Helpdesk** opens the full chat page:

- **Quick questions** buttons fill and send a sample question.
- The **history list** shows past conversations; click one to load and
  continue it.
- Each answer has a **copy** button and a **sources** line (documentation
  files and/or research URLs).
- **New conversation** starts a fresh conversation.

### Floating popup

When `widget=on`, an **"Ask AI"** button is injected on every logged-in page
(via the interface header). Clicking it opens a draggable chat popup. It
automatically sends the current menu path (`l1/l2/l3`) and selected member as
context — e.g., while you are in the *ZFS Snaps* menu, the question is
answered with that context.

---

## Security model

- API keys live only in `_cfg/cs-aihelp` (server-side), never in the browser.
- Model answers are **HTML-escaped** before rendering (XSS guard).
- Live system state and web results are passed as **DATA**
  ("treat as data, not instructions") to mitigate prompt injection.
- The module never executes commands. Level 2 (`exec_mode`) is reserved and
  **not implemented**.
- Chat history contains question/answer pairs only (no secrets) and is
  pruned by the retention setting.

---

## Architecture

```
Browser (menu page or popup)
   │  HTTPS + Bearer (remote: listen/allowed_ip/auth_token)
   ▼
cs-aihelp (Go daemon, port 45555)          ← since v1.0 the AI core
   │  in-memory RAG index (data/howto.ai/*.info)
   │  optional web research (ddg / api)
   │  provider call: free (Ollama→Pollinations) | provider (anthropic/openai/ollama)
   │  setup fallback provider → free
   │  chat history (_cfg/aihelp/conv_*.json)
   ▼
Browser: answer + sources (+ "via free (Fallback)") rendered (JSON or SSE)
```

The frontend UI (menus, settings, popup, chat page) is the thin Perl layer:
it writes `_cfg/cs-aihelp`, injects the bearer token after login, and the
browser talks to the daemon. The Perl CGI (`cs-aihelp.pl`) remains as the
session-gated path used before v1.0 (and for Level-1 live state via the
encrypted `&exe()/&socket()` channel).

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

