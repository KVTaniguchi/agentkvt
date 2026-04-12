# AgentKVT Execution Roadmap

This document translates the project vision into an execution-oriented roadmap. It answers:

- What is the smallest believable MVP?
- What exists already in the repo?
- What remains aspirational?

Use alongside [SOVEREIGN_PLANNER_VISION.md](SOVEREIGN_PLANNER_VISION.md), [FOUNDATIONAL_PLAN.MD](../FOUNDATIONAL_PLAN.MD), and [SUPERAGENT_IMPLEMENTATION_PHASES.md](SUPERAGENT_IMPLEMENTATION_PHASES.md).

## Product Goal

Build a private, local-first planning system where:

- the macOS Brain decomposes objectives into tasks, researches them, and generates structured outputs
- the iOS Remote presents research results, reviewable follow-up loops, deterministic user actions, and clear live-work monitoring
- the Rails backend on Mac acts as the system of record for objectives, tasks, research snapshots, action items, and logs
- model usage remains local, constrained, and inspectable

## MVP Definition

### MVP outcome

A user can:

1. Define an objective on iPhone (e.g. "Plan San Diego trip logistics")
2. Let the server decompose it into tasks
3. Let the Mac agent research each task using web search and local LLM
4. View structured research results back on iPhone
5. Receive `ActionItem`s with concrete next steps
6. Inspect an `AgentLog` trail showing the research and synthesis

### MVP scope

- shared data schema for Objectives, Tasks, ResearchSnapshots, ActionItems, AgentLogs, LifeContext
- iOS UI for creating objectives, reviewing plans and follow-ups, monitoring live work, viewing research results, and managing actions
- Rails backend with objective planning, task dispatch, and result persistence
- macOS runner that executes tasks via ObjectiveExecutionPool with bounded concurrency
- local LLM integration through Ollama
- at least one end-to-end objective flow that produces useful research
- basic auditability through AgentLog

### Not required for MVP

- automatic LifeContext self-updates from transcripts
- advanced CoreML/NLP preprocessing
- hardware auto-tuning across Apple Silicon tiers
- deep autonomous execution without user review

## Current Status (April 2026)

All major components are implemented with real business logic. The system runs in production on a dedicated M4 Max MacBook Pro.

### Implemented

- **Rails API backend** — full CRUD for objectives with task decomposition via `ObjectivePlanner`; `TaskExecutorJob` dispatches work to Mac agents; workspace isolation via `X-Workspace-Slug`; bearer token auth for agent endpoints; `ObjectivePresentationBuilder` for generative results UI
- **Mac runner** — event-driven `AgentExecutionQueue`; `ObjectiveExecutionPool` with configurable concurrent workers; `AgentTaskRunner` with retry logic for refusals and missing tool calls; tool registry with 20+ tools; `BackendAPIClient` for API integration
- **iOS app** — objective CRUD with plan approval and run/rerun/reset controls; generative results view via `ObjectivePresentationBuilder`; `Latest Follow-up` / `Follow-up Loop`; Objective Detail live monitoring with `Working On Now` and `Likely next check-in`; action items with intent routing; agent log view; chat interface; inbound file uploads; family member profiles; backend bootstrap on launch
- **ManagerCore** — shared Swift package with SwiftData models (ActionItem, AgentLog, FamilyMember, LifeContext, ChatThread, ChatMessage, WorkUnit, EphemeralPin, ResourceHealth, ResearchSnapshot, InboundFile, IncomingEmailSummary)
- **Structured logging** — AgentLog phases include start, tool_call, tool_result, assistant, assistant_final, outcome, error, warning
- **Email ingestion** — IMAP poller + EmailIngestor + sanitization pipeline
- **Research pipeline** — multi_step_search, read/write_objective_snapshot, read/write_research_snapshot tools
- **Sync** — Backend API is authoritative; iOS and Mac both sync via HTTP

### Partial or in progress

- **Flagship objective archetype** — no single objective pattern has been deeply tuned for repeated real-world value
- **Inbound data sanitization** — email sanitization exists, but broader privacy hardening for file ingestion is incomplete
- **Bee AI integration** — HTTP client exists but default API paths predate Bee's documented routes

### Aspirational

- automatic hardware-tier model selection
- deeper Apple-native NLP/CoreML orchestration
- rich context learning from passive sources
- fully mature "life manager" across all domains

## Existing vs Aspirational

| Area | Status | Notes |
|---|---|---|
| Shared data model | Done | Core entities in ManagerCore + Rails schema. |
| iOS objective + actions UI | Done | Full objective lifecycle, research results, action items, chat. |
| macOS brain | Done | Event-driven scheduler, ObjectiveExecutionPool, AgentTaskRunner. |
| Local LLM usage | Done | Ollama with tool-calling (llama4:latest default). |
| Rails backend | Done | Full API surface; objective planning + task dispatch. |
| Structured audit logging | Done | Phase-based AgentLog in backend; exposed in iOS. |
| Research pipeline | Done | multi_step_search, objective snapshots, research delta tracking. |
| Email ingestion | Done | IMAP + sanitization + incoming_email_trigger. |
| Ingestion privacy hardening | Partial | Email sanitization works; file ingestion less hardened. |
| Flagship objective archetype | Not started | No pattern tuned for repeated use. |
| Hardware-aware scaling | Aspirational | Vision exists; no implementation. |

## Milestones

### Milestone 1: Close the core loop ✅

- Objective created on iOS runs research on macOS
- Tasks produce ResearchSnapshots visible in iOS
- AgentLog entries trace the full pipeline
- One documented E2E flow works

### Milestone 2: Harden privacy and ingestion

- Inbound file and email flows consistently sanitized
- Ingestion failures visible in logs
- Sensitive data handling rules documented

### Milestone 3: Ship one excellent objective archetype

- One objective pattern delivers repeated value (e.g. trip planning, job search)
- Prompts, tools, and output quality are tuned for predictable behavior

### Milestone 4: Expand toward the sovereign planner vision

- Transcript-driven context updates
- Better local reasoning pipelines
- Hardware-tier model selection
- Additional objective templates for family, finance, and household planning

## Key Decisions To Preserve

- Objectives + deterministic actions remain the primary interaction model
- Tools stay sandboxed and explicitly allowlisted
- Personal data is sanitized locally before model exposure
- Local-first execution is the baseline; Rails runs on the same Mac as the agent
- The backend API is the system of record
