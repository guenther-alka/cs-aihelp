# Changelog

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
