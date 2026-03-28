# AgentKVT Execution Roadmap

This document translates the project vision into an execution-oriented roadmap. It is intended to answer three questions clearly:

- What is the smallest believable MVP?
- What appears to exist already in the repo?
- What remains aspirational and should be planned deliberately?

Use this alongside [SOVEREIGN_PLANNER_VISION.md](SOVEREIGN_PLANNER_VISION.md), [FOUNDATIONAL_PLAN.MD](../FOUNDATIONAL_PLAN.MD), and [SUPERAGENT_IMPLEMENTATION_PHASES.md](SUPERAGENT_IMPLEMENTATION_PHASES.md).

## Product Goal

Build a private, local-first planning system where:

- the macOS Brain runs missions and generates structured outputs
- the iOS Remote presents those outputs as deterministic user actions, with chat available for guided follow-up
- the Rails backend on Mac acts as the system of record for missions, action items, and logs
- model usage remains local, constrained, and inspectable

> **Architecture note:** The sync layer was pivoted from CloudKit-as-primary to a Mac-hosted Rails API as the system of record. SwiftData and CloudKit remain in use as a local cache and fallback, but the backend API is now the authoritative source for missions, action items, and logs. See [BACKEND_PIVOT_HANDOFF.md](BACKEND_PIVOT_HANDOFF.md) for the full rationale.

## MVP Definition

The MVP should prove the core closed loop, not the entire long-term vision.

### MVP outcome

A user can:

1. Define a mission on iPhone
2. Let the Mac run that mission on a schedule with an allowed tool set
3. Receive one or more `ActionItem`s back on iPhone
4. Inspect an `AgentLog` trail showing that the run happened

### MVP scope

The MVP should include:

- shared data schema for `LifeContext`, `MissionDefinition`, `ActionItem`, `AgentLog`, and inbound-file support
- iOS UI for viewing action items, editing missions, and managing life context
- macOS runner that can execute scheduled missions with a restricted tool allowlist
- local LLM integration through Ollama
- at least one end-to-end mission flow that creates useful `ActionItem`s
- basic auditability through `AgentLog`

### Explicitly not required for MVP

The MVP does not need to fully deliver:

- automatic `LifeContext` self-updates from transcripts
- advanced CoreML/NLP preprocessing pipelines
- polished multi-device sync reliability across real-world edge cases
- deep autonomous execution without user review
- broad hardware auto-tuning across all Apple Silicon tiers
- fully comprehensive tool-call tracing

## Current Repo Snapshot (as of March 2026)

All major components are implemented with real business logic. This is no longer a vertical slice — it is a functioning system at the code level. The primary open question is whether the E2E loop closes reliably in practice.

### Implemented and verified by code review

- **Rails API backend** — full CRUD for missions, action items, agent logs, family members; workspace isolation via `X-Workspace-Slug`; bearer token auth for Mac agent endpoints; `MissionSchedule` service with daily/weekly scheduling and `last_run_at` idempotency; integration tests covering the full agent workflow
- **Mac runner** — scheduler, `OllamaClient` (llama3.2 on localhost:11434), tool registry with ~13 tools, `BackendAPIClient` for writing results back to the server, `MissionLogWriter` with structured phases
- **iOS app** — mission CRUD with validation, action item display with intent routing, backend sync via `IOSBackendSyncService`, bootstrap on launch, family member profiles, log view
- **ManagerCore** — shared Swift package with `MissionDefinition`, `ActionItem`, `AgentLog`, `FamilyMember`, `LifeContext`, `ChatThread`, and supporting models
- **Structured logging** — `AgentLog` phases include `start`, `tool_call`, `assistant`, `outcome`, and `error`; logs are stored in the backend and visible in iOS

### Partial or unverified

- **E2E run in practice** — all code exists, but there is no documented evidence of a real mission completing end-to-end and producing useful `ActionItem`s
- **Dual sync path complexity** — backend API is primary, but CloudKit/SwiftData remain as a secondary path; this creates two sync surfaces to keep aligned
- **Inbound data sanitization** — email and dropzone ingestion tools exist, but privacy hardening and normalization before LLM exposure appear incomplete
- **Mission quality** — no flagship mission has been tuned for repeatable, real-world usefulness
- **`fetch_bee_ai_context` tool** — registered in the tool registry but likely a stub

### Recently completed

- **Output contract** — the `write_action_item` tool now includes the full per-intent `payloadJson` schema in its description (so Ollama receives it on every run). The iOS mission authoring UI explains that selected tools are injected automatically at runtime, and the Mac runner appends visible-output guidance whenever `write_action_item` is allowed. The Mac runner still emits a `"warning"` phase log if a mission completes without ever calling `write_action_item`. The canonical payload schema is defined in `ManagerCore/Sources/ManagerCore/SystemIntent.swift` and shared across both targets.

### Still aspirational

- automatic hardware-tier model selection and graceful degradation
- deeper Apple-native NLP/CoreML orchestration beyond current LLM-first flows
- rich context learning from BEE AI and other passive sources
- fully mature "life manager" behavior across work, finance, family, and household domains
- a truly polished sovereign planning experience with predictable, low-drift mission design patterns

## Existing vs Aspirational

| Area | Current status | Notes |
|---|---|---|
| Shared data model | Done | Core entities in ManagerCore; backend schema mirrors them. |
| iOS deterministic remote + chat | Done | Full UI for actions, missions, context, logs, and chat tab. |
| macOS brain | Done | Runner, scheduler, tool registry, and Ollama integration all implemented. |
| Tool allowlisting | Done | Per-mission `allowed_mcp_tools` JSONB array; enforced in runner and tested. |
| Local LLM usage | Done | Ollama integration with tool-calling support (llama3.2 default). |
| Rails backend as system of record | Done | Full API surface implemented; agent auth via bearer token. |
| Scheduler idempotency | Done | `last_run_at` tracking in backend; daily/weekly schedule semantics tested. |
| Structured audit logging | Done | Phase-based `AgentLog` in backend; exposed in iOS log view. |
| Sync (primary path) | Done | Backend API is authoritative; iOS and Mac both sync via HTTP. |
| Output contract for write_action_item | Done | Per-intent payload schema in tool description, runtime-injected authoring guidance, no-output warning log. |
| Ingestion pipeline | Partial | Email/dropzone tools exist; privacy sanitization not hardened. |
| Dual sync path (CloudKit + API) | Partial | Works as fallback; risk of divergence between the two paths. |
| E2E run verified in practice | Unverified | Code is complete; no documented successful real run on record. |
| Flagship mission archetype | Not started | No mission has been selected and tuned for repeated real-world use. |
| Hardware-aware scaling | Aspirational | Vision exists; no implementation. |
| Apple-native NLP/CoreML-first planning | Aspirational | Strong direction; not yet the dominant implementation story. |

## Milestones

### Milestone 1: Close the core loop ✅ (code complete, E2E unverified)

Goal: Make the current vertical slice consistently trustworthy.

Success looks like:

- a mission created on iOS runs on macOS without manual seeding
- the run creates deterministic `ActionItem`s
- `AgentLog` entries make failures and outcomes understandable
- one documented E2E flow works reliably for repeated testing

Status: All code for this milestone is implemented. The remaining work is to run the system end-to-end, confirm the loop closes in practice, and document the verified happy path. The scheduler, sync, output contracts, and logging are all in place.

### Milestone 2: Harden privacy and ingestion

Goal: Make personal data ingestion safe, local, and dependable.

Success looks like:

- inbound file and email flows are consistently sanitized
- mission inputs are normalized into predictable context structures
- ingestion failures are visible in logs
- sensitive data handling rules are documented clearly

Recommended focus:

- define sanitization boundaries before LLM exposure
- add tests for transcript, CSV, and email ingestion paths
- standardize how inbound data is attached to mission runs

### Milestone 3: Improve trust and observability

Goal: Reduce black-box behavior and make mission execution auditable.

Success looks like:

- logs show mission start, tool calls, outputs, and failure reasons
- users can understand why an `ActionItem` appeared
- repeated runs are easier to debug

Status: The phase-based `AgentLog` structure is implemented. The remaining work is validating that logs are rich enough in practice to debug failures, and surfacing enough detail in the iOS log view.

Recommended focus:

- validate log coverage against a real mission run
- expose enough log detail in iOS to support review and debugging without guesswork

### Milestone 4: Ship one excellent mission archetype

Goal: Prove product value with one deeply useful mission, not many shallow ones.

Best candidates:

- `Job Scout`
- `Budget Sentinel`

Success looks like:

- one mission delivers repeated value over multiple real runs
- prompts, tools, and output schema are tuned for predictable behavior
- the user can review and act through structured actions, with chat available for clarifications when needed

Status: Not started. No flagship mission has been selected or tuned.

### Milestone 5: Expand toward the sovereign planner vision

Goal: Move from a working agent platform to a true life-management system.

Focus areas:

- transcript-driven context updates
- better local reasoning pipelines using Apple-native NLP/CoreML
- hardware-tier model selection
- stronger cross-device reliability
- additional mission templates for family, finance, and household planning

## Recommended Near-Term Backlog

1. **Run the system end-to-end and document the result** — confirm that a mission created on iOS runs on Mac and produces `ActionItem`s visible in iOS; document the verified happy path in `E2E_VERIFICATION.md`
2. **Resolve the dual sync path** — decide whether CloudKit/SwiftData remains a supported path or becomes dev-only; eliminate ambiguity so debugging is unambiguous
3. **Harden inbound-data sanitization and mission-context shaping** — define the boundary between raw inbound data and what reaches the LLM
4. **Pick one flagship mission and optimize it for repeatable usefulness** — tune prompt, tools, and output schema for a single real-world scenario

Items 3 and 4 from the original backlog (scheduler idempotency, `AgentLog` expansion) are now implemented.

## Key Product Decisions To Keep Stable

To avoid drift, these decisions should remain the default unless we intentionally change course:

- deterministic actions remain the primary interaction model, with chat as a complementary interface
- mission outputs should become structured `ActionItem`s
- tools should stay sandboxed and explicitly allowlisted per mission
- personal data should be sanitized locally before broad model exposure
- local-first execution should be the baseline; the Rails backend runs on the same Mac as the agent runner
- the backend API is the system of record; CloudKit/SwiftData is a cache, not an authority

## Working Definition of Done

A roadmap item should generally be considered done when:

- the user-visible flow works
- the behavior is documented in `Docs/`
- the relevant path has test coverage or a repeatable verification procedure
- logs are good enough to debug failures without guesswork
- the change moves the system closer to deterministic, private, local-first planning

## Suggested Immediate Execution Order

The system architecture is complete. The best next sequence is:

1. run the system end-to-end for one mission and confirm the loop closes in practice
2. document the verified happy path and any gaps found during the run
3. decide on the dual sync path (backend-only vs. backend + CloudKit)
4. select and refine a single flagship mission for MVP
