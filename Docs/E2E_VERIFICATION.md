# End-to-End Verification and Audit

## E2E Test Scenarios

These missions are **not hardcoded** in the binary. Create them via the iOS app (Missions tab) or by inserting `MissionDefinition` records into the shared store. Use the following as the prompt and tool configuration for testing.

### Test Mission 1: Career (Job Scout)

- **Mission name:** Tech Job Scout
- **System prompt (example):** "You are a job scout. Search for iOS developer roles within 15 miles of the user's location. Cross-reference with a local resume file if the user has one. For each high-match role, use the write_action_item tool to create an action with title like 'Review: [Company] - [Role]' and systemIntent 'review_job'. Summarize how many leads you found."
- **Trigger schedule:** `daily|08:00` or `weekly|monday`
- **Allowed MCP tools:** `["write_action_item"]` (add `send_notification_email` if you want alerts)

**Verification:** Run the Mac scheduler (or trigger the mission at the scheduled time). Check that ActionItems appear on the iOS dashboard with job-lead titles and that AgentLog has an outcome entry for the mission.

### Test Mission 2: Finance (Budget Sentinel)

- **Mission name:** Budget Sentinel
- **System prompt (example):** "You monitor spending. The user exports transactions to CSV. When you find impulse purchases or spending over a set limit, use write_action_item to create an action with title 'Review impulse purchase: [description]' and systemIntent 'review_purchase'. Only create items when limits are exceeded."
- **Trigger schedule:** `daily|09:00` or `weekly|friday`
- **Allowed MCP tools:** `["write_action_item"]`

**Verification:** After the mission runs (with CSV data available to the agent via a tool or LifeContext), confirm that ActionItems appear when limits are exceeded and that AgentLog records the run.

## AgentLog Audit

- **MissionRunner** (AgentKVTMac) writes one **AgentLog** entry per mission run with `phase: "outcome"` and the final result (or error) in `content`.
- For full audit (reasoning and tool calls), extend the agent loop to append log entries during the run (e.g. before/after each tool call and for each LLM turn). The current implementation provides at least the final outcome per mission.

**Review path:** Use the iOS app or a separate viewer to query `AgentLog` by `missionId` or `missionName` and sort by `timestamp`.

## Sync and Stability Checklist

- [ ] **SwiftData sync:** If using CloudKit or local sync, both Mac and iOS use the same ManagerCore schema and container configuration so that MissionDefinition and ActionItem replicate correctly.
- [ ] **No hardcoded missions:** Missions are created only via the iOS UI or data seed; none are compiled into the app.
- [ ] **LLM throttling:** See `Docs/LLM_THROTTLING.md`. Ensure the local LLM host is configured (or missions are scheduled) so that heavy agent loops do not lock the system; preserve ~20% headroom where possible.

## Running the Mac Runner

- **One-off test:** `cd AgentKVTMac && swift run AgentKVTMacRunner` (no scheduler; runs single test prompt and writes one ActionItem if Ollama is available).
- **Scheduler mode:** `RUN_SCHEDULER=1 swift run AgentKVTMacRunner` (polls missions on an interval; set `SCHEDULER_INTERVAL_SECONDS` if needed).
- **Optional env:** `NOTIFICATION_EMAIL`, `GITHUB_AGENT_PAT`, `GITHUB_AGENT_REPOS`, `OLLAMA_BASE_URL`, `OLLAMA_MODEL`.
