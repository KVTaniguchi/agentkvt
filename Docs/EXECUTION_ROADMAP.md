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
- SwiftData acts as the shared memory and audit layer
- model usage remains local, constrained, and inspectable

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

- shared SwiftData schema for `LifeContext`, `MissionDefinition`, `ActionItem`, `AgentLog`, and current inbound-file support
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

## Current Repo Snapshot

Based on the current code and docs, AgentKVT appears to already have a meaningful vertical slice.

### Likely implemented

- `ManagerCore` shared models and Swift package
- `AgentKVTMac` runner, mission scheduler, mission runner, and tool registry
- local Ollama integration
- multiple tools, including action writing, web, GitHub, email, inbound, and browser-scanning tools
- iOS SwiftUI app with dashboard, missions, context, and log views
- tests for models, scheduler behavior, tool registry, and parts of inbound flows
- foundational docs for data flow, sync, throttling, E2E verification, tool IDs, and dropzone behavior

### Likely partial or unverified

- real sync reliability between macOS and iOS
- CloudKit readiness versus local-only assumptions in docs
- scheduler correctness around duplicate prevention and idempotency
- full audit logging for intermediate reasoning and tool calls
- mission quality and usefulness for real-world user workflows
- hardened privacy pipeline for all ingestion types

### Still aspirational

- automatic hardware-tier model selection and graceful degradation
- deeper Apple-native NLP/CoreML orchestration beyond current LLM-first flows
- rich context learning from BEE AI and other passive sources
- fully mature "life manager" behavior across work, finance, family, and household domains
- a truly polished sovereign planning experience with predictable, low-drift mission design patterns

## Existing vs Aspirational

| Area | Current read | Notes |
|---|---|---|
| Shared data model | Present | Core entities and package structure exist. |
| iOS deterministic remote + chat | Present | UI exists for actions, missions, context, logs, and a dedicated chat tab. |
| macOS brain | Present | Runner, scheduler, and mission pipeline appear implemented. |
| Tool allowlisting | Present | Tool registry and mission tool restrictions are documented and tested. |
| Local LLM usage | Present | Ollama integration exists. |
| Ingestion pipeline | Partial | Email/dropzone paths exist, but privacy and normalization likely need hardening. |
| Auditability | Partial | Final mission outcomes are logged; full traceability appears incomplete. |
| Sync | Partial | Some code/config exists, but docs suggest uncertainty or deferred completeness. |
| Hardware-aware scaling | Aspirational | Vision exists; implementation strategy is not yet a finished product capability. |
| Apple-native NLP/CoreML-first planning | Aspirational | Strong direction, but not yet the dominant implementation story. |

## Milestones

## Milestone 1: Close the core loop

Goal: Make the current vertical slice consistently trustworthy.

Success looks like:

- a mission created on iOS runs on macOS without manual seeding
- the run creates deterministic `ActionItem`s
- `AgentLog` entries make failures and outcomes understandable
- one documented E2E flow works reliably for repeated testing

Recommended focus:

- validate the scheduler and due-mission semantics
- tighten output contracts for `ActionItem` creation
- verify the shared store and sync assumptions
- document the exact happy path for one mission from creation to review

## Milestone 2: Harden privacy and ingestion

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

## Milestone 3: Improve trust and observability

Goal: Reduce black-box behavior and make mission execution auditable.

Success looks like:

- logs show mission start, tool calls, outputs, and failure reasons
- users can understand why an `ActionItem` appeared
- repeated runs are easier to debug

Recommended focus:

- extend `AgentLog` coverage beyond final outcomes
- define a minimal structured event model for mission execution
- expose enough log detail in iOS to support review and debugging

## Milestone 4: Ship one excellent mission archetype

Goal: Prove product value with one deeply useful mission, not many shallow ones.

Best candidates:

- `Job Scout`
- `Budget Sentinel`

Success looks like:

- one mission delivers repeated value over multiple real runs
- prompts, tools, and output schema are tuned for predictable behavior
- the user can review and act through structured actions, with chat available for clarifications when needed

## Milestone 5: Expand toward the sovereign planner vision

Goal: Move from a working agent platform to a true life-management system.

Focus areas:

- transcript-driven context updates
- better local reasoning pipelines using Apple-native NLP/CoreML
- hardware-tier model selection
- stronger cross-device reliability
- additional mission templates for family, finance, and household planning

## Recommended Near-Term Backlog

If we want the highest-value next work, the backlog should probably be:

1. Verify the end-to-end path for one mission from iOS authoring to iOS action display
2. Resolve the sync story so docs and runtime behavior agree
3. Improve scheduler idempotency and duplicate-run protection
4. Expand `AgentLog` into a more useful execution trace
5. Harden inbound-data sanitization and mission-context shaping
6. Pick one flagship mission and optimize it for repeatable usefulness

## Key Product Decisions To Keep Stable

To avoid drift, these decisions should remain the default unless we intentionally change course:

- deterministic actions remain the primary interaction model, with chat as a complementary interface
- mission outputs should become structured `ActionItem`s
- tools should stay sandboxed and explicitly allowlisted
- personal data should be sanitized locally before broad model exposure
- local-first execution should be the baseline, with cloud dependency treated as optional

## Working Definition of Done

A roadmap item should generally be considered done when:

- the user-visible flow works
- the behavior is documented in `Docs/`
- the relevant path has test coverage or a repeatable verification procedure
- logs are good enough to debug failures without guesswork
- the change moves the system closer to deterministic, private, local-first planning

## Suggested Immediate Execution Order

If we continue directly from this document, the best next sequence is:

1. audit the current E2E path for one mission
2. reconcile sync and schema documentation with actual runtime behavior
3. tighten scheduler and logging reliability
4. select and refine a single flagship mission for MVP

This keeps us focused on proving a trustworthy core loop before chasing the broader sovereign-planner feature set.
