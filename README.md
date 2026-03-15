# AgentKVT Project

Localized, closed-loop agentic system: **Brain** (macOS) + **Remote** (iOS), with a shared SwiftData bridge.

## Repo layout

- **ManagerCore/** — Swift package: shared SwiftData schema (LifeContext, MissionDefinition, ActionItem, AgentLog). Used by both Mac and iOS.
- **AgentKVTMac/** — macOS agent: MCP-style tool registry, Ollama client, mission runner, scheduler. Runner executable for one-off test or `RUN_SCHEDULER=1` for CRON-style runs.
- **AgentKVTiOS/** — iOS app (Xcode project): SwiftUI dashboard (Actions, Missions, Context, Agent Log). No chat UI.
- **Docs/** — SYNC.md, LLM_THROTTLING.md, TOOL_IDS.md, E2E_VERIFICATION.md.

## Quick start

1. **ManagerCore:** `cd ManagerCore && swift build`
2. **Mac runner (test):** `cd AgentKVTMac && swift run AgentKVTMacRunner` (requires Ollama on localhost; writes one test ActionItem).
3. **Mac scheduler:** `RUN_SCHEDULER=1 swift run AgentKVTMacRunner` (polls missions; set env for notification/GitHub tools if needed).
4. **iOS:** Open `AgentKVTiOS/AgentKVTiOS.xcodeproj` in Xcode, set Development Team, build and run.

## Planning

- [FOUNDATIONAL_PLAN.MD](FOUNDATIONAL_PLAN.MD) — Architecture, schema, missions, tools, diagram.
- [Docs/E2E_VERIFICATION.md](Docs/E2E_VERIFICATION.md) — E2E scenarios (Career, Finance), AgentLog audit, checklist.

Out of scope: DIYProjectManager retooling; see README for planning history.
