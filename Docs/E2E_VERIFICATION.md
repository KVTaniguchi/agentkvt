# End-to-End Verification

This document defines the verification path for AgentKVT's core loop:

1. Create an objective on iOS
2. Let the Rails backend decompose it into tasks
3. Let the Mac Brain research each task
4. Inspect research results and action items on iOS

## Success Criteria

An E2E pass is successful when all of the following are true:

- an objective created in the iOS app is persisted in the Rails backend
- the backend decomposes it into at least one task
- the Mac Brain receives task webhooks and begins research
- the agent produces at least one `ResearchSnapshot`
- `AgentLog` contains start, tool_call, tool_result, and outcome entries for the run
- the iOS app shows research results in the objective detail view
- any created `ActionItem`s are visible in the Actions tab

## Recommended First Scenario

### Objective: Plan a Weekend Trip

- **Goal:** "Plan a weekend trip to San Diego"
- **Status:** active (triggers automatic task decomposition)

Why this scenario first:

- it exercises the full objective → task → research → results loop
- it uses web search tools that produce concrete, verifiable output
- it has clear success criteria (research results with hotels, activities, etc.)

## E2E Checklist

### 1. Prepare the iOS app

Open [AgentKVTiOS/GETTING_STARTED.md](../AgentKVTiOS/GETTING_STARTED.md) and launch the app.

Verify:
- the app opens successfully
- the Objectives tab is visible
- the Actions tab is accessible
- the Log tab opens

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
3. Enter "Plan a weekend trip to San Diego"
4. Leave "Start immediately (Active)" toggled on
5. Tap Save

Verify:
- the objective appears in the list with "Active" status
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
- Research results should appear as structured content
- The Log tab should show execution entries
- Any created ActionItems should appear in the Actions tab

### 7. Run controls

Test the objective run controls:

- **Run Now** — re-triggers task execution for pending tasks
- **Reset Stuck & Run** — resets tasks stuck in `in_progress` and re-runs
- **Rerun** — creates fresh tasks and runs the objective again

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
- Check that `IOSBackendSyncService` is configured with the correct API URL

## Fast Local Runner Check

For a runner-only smoke test:

```bash
cd AgentKVTMac
swift run AgentKVTMacRunner
```

This runs a single test that creates one ActionItem via `write_action_item`. It does not test the objectives pipeline.
