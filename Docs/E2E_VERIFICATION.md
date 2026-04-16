# End-to-End Verification

This document defines the verification path for AgentKVT's core loop:

1. Create an objective on iOS
2. Let the Rails backend decompose it into tasks
3. Let the Mac Brain research each task
4. Inspect research results and live work state on iOS

## Success Criteria

An E2E pass is successful when all of the following are true:

- an objective created in the iOS app is persisted in the Rails backend
- the backend decomposes it into at least one task
- the Mac Brain receives task webhooks and begins research
- the agent produces at least one `ResearchSnapshot`
- `AgentLog` contains start, tool_call, tool_result, and outcome entries for the run
- the iOS app shows research results in the Research screen and a clear next-step state in Objective Detail

## Recommended First Scenario

### Objective: Plan a Weekend Trip

- **Goal:** "Plan a weekend trip to San Diego"
- **Status:** active (triggers automatic task decomposition)

Why this scenario first:

- it exercises the full objective → task → research → results loop
- it uses web search tools that produce concrete, verifiable output
- it has clear success criteria (research results with hotels, activities, etc.)

## Guided Composer Scenarios

These scenarios verify the new guided objective composer before exercising the full objective execution loop.

### Scenario: Date Night

- Seed prompt: "Help me plan a date night"
- Template: `date_night`
- Status: active

Verify:
- the composer asks 1-2 focused follow-up questions about budget, timing, and preferences
- the live summary card fills in context, constraints, preferences, and success criteria without requiring copy-paste from another LLM
- the review screen shows a concise canonical goal and the exact planner-facing summary
- after finalizing, the created objective contains structured brief data and produces tasks tailored to the stated budget, location, and vibe

### Scenario: Budget

- Seed prompt: "Help me make a budget"
- Template: `budget`
- Status: active

Verify:
- the composer asks focused follow-up questions about income cadence, major expenses, and budgeting goals
- the live summary card highlights any missing planning inputs before finalization
- the finalized objective stores structured brief data and a canonical goal instead of only the original seed phrase
- the resulting task list reflects the captured constraints and success criteria rather than generic financial advice

## E2E Checklist

### 1. Prepare the iOS app

Open [AgentKVTiOS/GETTING_STARTED.md](../AgentKVTiOS/GETTING_STARTED.md) and launch the app.

Verify:
- the app opens successfully
- the Objectives tab is visible
- objective detail loads without a dedicated Log tab

### 2. Prepare the Rails backend

Ensure the Rails API is running on the server Mac:

```bash
curl -sS http://127.0.0.1:3000/healthz
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for setup details.

### 3. Prepare the Mac Brain

Start the Mac runner in scheduler mode:

```bash
cd AgentKVTMac
RUN_SCHEDULER=1 SCHEDULER_INTERVAL_SECONDS=30 swift run AgentKVTMacRunner
```

Or launch the signed macOS app with the runner plist configured.

Verify in the Mac logs:
- the scheduler starts
- webhook listener is active
- the ObjectiveExecutionPool starts its workers

### 4. Create the objective on iOS

In the iOS app:

1. Open the Objectives tab
2. Tap **+**
3. Pick a starter template or keep the generic flow
4. Either type a short seed phrase and continue the guided draft, or use the legacy fallback form if the composer API is unavailable
5. Review the canonical goal and planner summary
6. Leave "Start immediately (Active)" toggled on
7. Tap Save

Verify:
- the objective appears in the list with "Active" status
- if the guided composer was used, the review screen should have shown structured context and missing-field guidance before saving
- after a few seconds, tasks should appear in the detail view

### 5. Wait for task execution

When the Mac Brain receives task webhooks, verify:

- the agent begins processing (visible in Mac logs)
- `multi_step_search` or `web_search_and_fetch` calls appear in logs
- `write_objective_snapshot` is called to persist findings

Expected Mac-side evidence:
- `[ObjectiveExecutionPool]` log entries for task processing
- `start`, `tool_call`, `tool_result`, `assistant_final` log phases

### 6. Verify iOS results

In the iOS app:

- Tap the objective to open the detail view
- The top `Activity` section should make the current state obvious:
  - `Plan ready for review` when the initial plan has not been approved yet
  - `Next step: Review follow-up` when a reviewable next pass is waiting
  - `No action needed right now` when the Mac is already working
- If work is active, verify that Objective Detail shows:
  - `Working On Now`
  - `Recently Finished` after at least one task completes
  - `Likely next check-in`
- Open the Research screen from Objective Detail when snapshots are available
- Research results should appear as structured content
- If follow-up feedback has been submitted, the Research screen should show:
  - `Latest Follow-up`
  - `Agent Activity`
  - `Follow-up Loop`
- Objective Detail should show recent execution activity

### 7. Verify run and recovery controls

Test the objective run controls:

- **Generate plan** — appears before the initial task batch exists
- **Start approved plan** — appears when a pending objective already has approved tasks
- **Run now (queue pending)** — appears when an active objective has queued work and no tasks are currently running
- **Dispatch queued tasks now** — appears only when tasks are already running and more queued work still exists
- **Reset stuck tasks & run** — resets tasks stuck in `in_progress` and re-runs
- **Rerun all tasks** — resets every task to `pending`, clears snapshots, and runs the objective again

### 8. Verify follow-up UX

Use this after the first research snapshots are available.

In the iOS app:

1. Open the Research screen.
2. Tap `Continue Research` or one of the quick-intent buttons.
3. Submit a follow-up request such as `Challenge this result and verify the source.`

Verify:
- the sheet first shows `Sending your feedback`
- then shows `Feedback received`
- the sheet cannot be dismissed during the blocking submit/build states
- on success, the sheet shows the resulting follow-up card with the correct status:
  - `Ready for review` when the next pass is still proposed
  - `Queued for agent` when work is active and ready to run
  - `Saved for later` when the objective is pending and the batch is stored
- after dismissing, the Research screen pins the new entry under `Latest Follow-up`
- Objective Detail reflects the same state:
  - `Next step: Review follow-up` when approval is needed
  - `No action needed right now` when the approved batch is already running

## Failure Checklist

### Objective never gets tasks

- Rails API may not be running
- `ObjectivePlannerJob` may have failed — check Rails logs
- Ollama may not be reachable from the Rails server

### Tasks created but never executed

- Mac runner is not running or not reachable via webhook
- Agent is not registered with the backend
- Webhook port may be blocked

### Agent runs but produces no snapshots

- `write_objective_snapshot` may not be in the allowed tools
- Agent may be producing refusal text instead of tool calls (check for retry nudges in logs)
- Ollama may be returning errors

### Results not visible on iOS

- iOS may not be connected to the same backend
- Refresh the objective detail view
- Refresh the Research screen if the follow-up sheet timed out and returned you to a polling state
- Check that `IOSBackendSyncService` is configured with the correct API URL

## Fast Local Runner Check

For a runner-only smoke test:

```bash
cd AgentKVTMac
swift run AgentKVTMacRunner
```

This runs the runner in single-run mode for a basic smoke test. It does not test the objectives pipeline.
