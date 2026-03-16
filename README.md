<div align="center">

# 🚧 IN PROGRESS 🚧

**This project is under active development. APIs, schema, and behavior may change.**

</div>

---

# AgentKVT

Localized, closed-loop agentic system: **Brain** (macOS) + **Remote** (iOS), with a shared SwiftData bridge. Define missions and life context on your iPhone; the Mac runner executes them on schedule and pushes action items back to your phone.

**Suggested GitHub topics** (set under repo **About** → **Topics** for discoverability):

`ai-agents` · `agent-platform` · `swift` · `swiftui` · `swiftdata` · `macos` · `ios` · `ollama` · `llm` · `mcp` · `local-ai` · `autonomous-agents` · `personal-agent` · `cloudkit`

## Screenshots

### iOS app (Remote)

| Actions | Missions | Context | Log |
|--------|----------|---------|-----|
| [![Actions](https://raw.githubusercontent.com/KVTaniguchi/agentkvt/main/Docs/screenshots/ios-actions.png)](https://github.com/KVTaniguchi/agentkvt/blob/main/Docs/screenshots/ios-actions.png) | [![Missions](https://raw.githubusercontent.com/KVTaniguchi/agentkvt/main/Docs/screenshots/ios-missions.png)](https://github.com/KVTaniguchi/agentkvt/blob/main/Docs/screenshots/ios-missions.png) | [![Context](https://raw.githubusercontent.com/KVTaniguchi/agentkvt/main/Docs/screenshots/ios-context.png)](https://github.com/KVTaniguchi/agentkvt/blob/main/Docs/screenshots/ios-context.png) | [![Log](https://raw.githubusercontent.com/KVTaniguchi/agentkvt/main/Docs/screenshots/ios-log.png)](https://github.com/KVTaniguchi/agentkvt/blob/main/Docs/screenshots/ios-log.png) |

**Actions** — Buttons created by the Mac agent (e.g. “Review: [Company] - Senior iOS Lead”). **Missions** — Define name, prompt, schedule, and allowed tools (e.g. Find a job, weekly). **Context** — Key/value facts the agent uses (goals, location). **Log** — Audit trail of what the agent did.

### Mac runner (Brain)

The Mac app has no GUI. When you SSH into the Mac Studio (or run locally), you see only terminal output:

![Mac terminal](https://raw.githubusercontent.com/KVTaniguchi/agentkvt/main/Docs/screenshots/mac-terminal.png)

### Data flow

![Data flow](https://raw.githubusercontent.com/KVTaniguchi/agentkvt/main/Docs/screenshots/data-flow.png)

iOS → shared SwiftData store → Mac scheduler → MissionRunner → AgentLoop + tools → ActionItem / AgentLog → back to iOS. See [Docs/DATA_FLOW.md](Docs/DATA_FLOW.md).

---

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
- [Docs/SUPERAGENT_IMPLEMENTATION_PHASES.md](Docs/SUPERAGENT_IMPLEMENTATION_PHASES.md) — Phased implementation plan (ManagerCore → Mac Brain → tools → mission engine → iOS → E2E).
- [Docs/E2E_VERIFICATION.md](Docs/E2E_VERIFICATION.md) — E2E scenarios (Career, Finance), AgentLog audit, checklist.

Out of scope: DIYProjectManager retooling; see README for planning history.
