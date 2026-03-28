# Bee Computer API — integration plan (AgentKVT)

This plan aligns the Mac tool **`fetch_bee_ai_context`** with [Bee’s official API](https://docs.bee.computer/docs/proxy), as described in the [Getting Started](https://docs.bee.computer/docs) and [Skill](https://docs.bee.computer/docs/skill) docs.

## What Bee provides

- **Product:** Personal memory (conversations, facts, todos, journals, daily summaries) with CLI export and agent-facing access.
- **Local HTTP:** `bee proxy [--port …]` serves **`/v1/*`** (Bee docs default **8787**). Intended for **local development**; do not expose to the public internet.
- **Direct API:** Same `GET/POST /v1/…` routes against Bee’s hosted base URL with **`Authorization: Bearer $BEE_TOKEN`**, using Bee’s **private CA** (not public PKI)—see [API](https://docs.bee.computer/docs/proxy) and the linked `certs` source in **bee-cli**.
- **Agent ecosystem:** [Bee Skill](https://docs.bee.computer/docs/skill) (`npx skills add bee-computer/bee-skill`) exposes richer agent workflows; AgentKVT may remain HTTP-only or adopt Skill patterns later.

## Current AgentKVT behavior

| Item | Status |
|------|--------|
| Tool | `fetch_bee_ai_context` in `AgentKVTMac/.../BeeAIContextTool.swift` |
| Transport | `URLSession` GET to `BEE_AI_BASE_URL` + path (default `v1/insights`) with `BEE_AI_API_KEY` Bearer token |
| Response parsing | Ad hoc JSON: `insights`, `transcriptions`, or `data` arrays—**not** the documented Bee entity shapes |
| Tests | `MOCK_BEE_AI_RESPONSE_JSON` for canned JSON |

The default path **`v1/insights`** is a **placeholder**; Bee’s documented routes include **`/v1/me`**, **`/v1/conversations`**, **`/v1/daily`**, **`POST /v1/search/conversations`**, **`GET /v1/stream`**, etc.

## Goals

1. **Configuration:** Support first-class **`bee proxy`** on localhost (base URL only, optional path override) with clear docs; optionally support direct API with CA trust documented.
2. **Data selection:** Replace the single “insights” fetch with a **defined bundle** of Bee data appropriate for mission context—for example:
   - `GET /v1/me` (profile)
   - `GET /v1/daily` or latest daily summary (brief)
   - `GET /v1/conversations` with a small limit or `GET /v1/changes` for incremental sync
   - Optional `POST /v1/search/conversations` when the mission supplies a search query (may require tool parameter additions later)
3. **Summarization:** Map Bee JSON to a **stable text block** for `LifeContext` / `AgentLog` (similar length cap as today’s ~500 char preview).
4. **Security:** Never bind `bee proxy` beyond localhost; document token handling; if using direct API, implement CA pinning or trust per Bee’s certificate bundle.
5. **Compatibility:** Keep **`MOCK_BEE_AI_RESPONSE_JSON`** for tests; add fixtures shaped like real `/v1/*` responses.

## Phased work

| Phase | Scope |
|-------|--------|
| **P0 — Docs & config** | Document `BEE_AI_BASE_URL=http://127.0.0.1:8787` (or chosen port), remove “wristband” wording everywhere; optional rename env vars to `BEE_PROXY_BASE_URL` / `BEE_TOKEN` aliases while keeping old names. |
| **P1 — Real endpoints** | Implement one concrete flow: e.g. fetch `/v1/me` + last N lines from `/v1/daily` or recent conversations; parse documented JSON; build summary string. Drop default `v1/insights` or gate it behind explicit opt-in. |
| **P2 — TLS direct API** | If needed outside proxy: URLSession delegate or pin Bee CA; read token from env/keychain; same response mapping as P1. |
| **P3 — Richer context** | Optional SSE `/v1/stream` or incremental `/v1/changes` for “heartbeat” missions; optional neural search; evaluate overlap with [Bee Skill](https://docs.bee.computer/docs/skill). |

## Open questions

- **Volume:** How many conversations / how much daily text to include per mission run to stay within LLM context and latency?
- **Identity:** Single Bee account per Mac brain, or per-workspace configuration later?
- **Search:** Should the tool accept an optional query argument for `POST /v1/search/conversations` (schema change to tool parameters)?

## References

- [Bee — Getting Started](https://docs.bee.computer/docs)
- [Bee — API (`bee proxy` and `/v1/*`)](https://docs.bee.computer/docs/proxy)
- [Bee — Skill](https://docs.bee.computer/docs/skill)
- [bee-cli on GitHub](https://github.com/bee-computer/bee-cli)
