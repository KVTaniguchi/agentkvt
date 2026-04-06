# Implementation Phases

Based on [FOUNDATIONAL_PLAN.MD](../FOUNDATIONAL_PLAN.MD) and [README.md](../README.md). All phases are implemented. This document reflects the current architecture.

---

## Architecture Summary

```text
+------------------+       HTTP (JSON)        +------------------------+
|  iOS App         | -----------------------> |  Rails API (:3000)     |
|  SwiftUI Remote  |       Tailscale/LAN      |  Objectives, Tasks,    |
|                  | <----------------------- |  Planner, Dispatch     |
+------------------+                         +------------+-------------+
                                                      |
                                                      | Active Record
                                                      v
                                           +------------------------+
                                           |  PostgreSQL            |
                                           +------------------------+
                                                      ^
                                                      |
+------------------+       HTTP (agent token)         |
|  Mac Brain       | --------------------------------+
|  AgentExecQueue  |
|  ObjectivePool   |       Local IPC
|  + Ollama        | <------> LLM inference
+------------------+
```

- **Brain (macOS):** Event-driven scheduler + ObjectiveExecutionPool with concurrent workers; inference via Ollama.
- **Remote (iOS):** SwiftUI dashboard with Objectives, Actions, Context, Log, Chat, and Files tabs.
- **Backend (Rails + Postgres):** System of record; objective planning, task dispatch, research persistence.
- **Bridge:** HTTPS/HTTP to the Rails API. SwiftData on each device for local concerns; Postgres is authoritative.

---

## Phase 1: Shared schema and package (ManagerCore) ✅

**Deliverables:**

- Swift Package `ManagerCore` containing:
  - **LifeContext** — static facts / user preferences
  - **ActionItem** — dynamic button data for iOS dashboard
  - **AgentLog** — append-only audit log
  - **FamilyMember** — in-app identity for family attribution
  - **ChatThread / ChatMessage** — conversational interface models
  - **WorkUnit / EphemeralPin / ResourceHealth** — stigmergy board models
  - **InboundFile** — uploaded file tracking
  - **ResearchSnapshot** — persisted research findings
  - **IncomingEmailSummary** — pre-summarized emails from CloudKit bridge
  - **~~MissionDefinition~~** — *(legacy, deprecated)* — superseded by server-side Objectives

---

## Phase 2: macOS Brain — MCP host and LLM integration ✅

**Deliverables:**

- macOS app target with background/headless capability
- MCP Server layer with zero-trust tool validation
- LLM integration via OllamaClient (tool-calling, JSON output)
- Dedicated-machine runtime guidance documented in [LLM_THROTTLING.md](LLM_THROTTLING.md)

---

## Phase 3: Sandboxed MCP tools ✅

**Deliverables (20+ tools implemented):**

- **write_action_item** — creates ActionItems for iOS dashboard
- **write_objective_snapshot / read_objective_snapshot** — persists/reads research findings via Rails API
- **web_search_and_fetch** — Ollama web search + page fetch
- **multi_step_search** — batched multi-query search
- **headless_browser_scout** — headless WebKit browsing
- **send_notification_email** — fixed-destination email
- **github_agent** — bot-scoped GitHub operations
- **fetch_bee_ai_context** — Bee personal context integration
- **incoming_email_trigger** — Agent Inbox email processing
- **get_life_context** — reads LifeContext entries
- **fetch_agent_logs** — reads recent execution logs
- **list_dropzone_files / read_dropzone_file** — file inbound access
- **fetch_work_units / update_work_unit** — stigmergy board
- **pin_ephemeral_note** — TTL-based ephemeral notes
- **list_resource_health / report_resource_failure / clear_resource_health** — resource cooldown
- **read_research_snapshot / write_research_snapshot** — local delta tracking

Full reference: [TOOL_IDS.md](TOOL_IDS.md)

---

## Phase 4: Objective pipeline (Mac + Server) ✅

**What replaced the old mission engine:**

- **Rails ObjectivePlanner** — LLM-assisted task decomposition on the server
- **TaskExecutorJob** — dispatches task webhooks to registered Mac agents
- **ObjectiveExecutionPool** — concurrent worker pool on Mac, bounded concurrency
- **AgentTaskRunner** — executes one task: LLM conversation with tool calls
- **Retry logic** — handles refusal boilerplate, raw JSON in text, missing tool calls
- **Tool batch policy** — defers `write_action_item` when data-gathering tools are in the same batch

The runner automatically appends runtime guidance for allowed tools and injects existing action item summaries to prevent duplicates.

---

## Phase 5: iOS Remote — dashboard, chat, and objectives ✅

**Deliverables:**

- SwiftUI app with backend-first sync via `IOSBackendSyncService`
- **Objectives tab:** Create objectives, view tasks, see generative research results, run/rerun/reset
- **Actions tab:** View and handle ActionItems with intent routing
- **Context tab:** Edit LifeContext entries
- **Log tab:** View AgentLog entries by phase
- **Chat tab:** Conversational interface with family profile attribution
- **Files tab:** Upload inbound files to the server
- Family member profiles with per-device selection

---

## Phase 6: End-to-end verification ✅

- E2E scenarios documented in [E2E_VERIFICATION.md](E2E_VERIFICATION.md)
- Production deployment documented in [DEPLOYMENT.md](DEPLOYMENT.md)
- System runs on dedicated M4 Max MacBook Pro

---

## Repo Layout

- `ManagerCore/` — Swift package (SwiftData models)
- `AgentKVTMac/` — macOS app (event-driven scheduler, ObjectiveExecutionPool, tools, OllamaClient)
- `AgentKVTiOS/` — iOS app (SwiftUI dashboard, backend sync)
- `server/` — Rails API (objectives, tasks, planning, dispatch)
- `Docs/` — architecture, deployment, data flow, tool reference

---

## Out of scope

- DIYProjectManager retooling is out of scope.
