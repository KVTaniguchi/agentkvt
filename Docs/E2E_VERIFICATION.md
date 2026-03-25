# End-to-End Verification

This document defines the current real-world verification path for AgentKVT's core loop:

1. create a mission on iOS
2. run the Mac Brain against the same shared store
3. let the mission produce `ActionItem` and `AgentLog` records
4. inspect those results on iOS

This has been updated to match the current codebase more closely, including mission identity propagation, richer logging, and the current sync constraints.

## Important Constraint

For a true shared-store E2E run, the Mac side must run as a signed macOS app target with the correct entitlements.

Why:

- the iOS app uses an app group plus CloudKit-backed SwiftData container
- the Swift Package executable invoked with `swift run AgentKVTMacRunner` does not get the same signed app entitlement path as an Xcode-built Mac app
- package tests prove the logic, but they do not prove cross-device sync

Use `swift run` for isolated runner checks. Use an Xcode-built macOS app target for real bridge verification.

## Current Success Criteria

An E2E pass should only count as successful if all of the following are true:

- a mission created in the iOS app is visible to the Mac Brain
- the Mac Brain executes it once when due
- the mission creates at least one `ActionItem`
- the created `ActionItem` retains the originating `missionId`
- `AgentLog` contains `start`, tool, and `outcome` entries for the run
- the iOS app shows the action in the Actions tab and its source mission in the detail view

## Recommended First Scenario

Start with a simple mission that only depends on `write_action_item`.

### Mission: Tech Job Scout

- **Mission name:** `Tech Job Scout`
- **Schedule:** `daily|08:00` or another near-future time you can test live
- **Allowed tools:** `write_action_item`
- **System prompt:**

```text
You are a job scout. Create one ActionItem summarizing a promising iOS role to review. Use the write_action_item tool exactly once. Set the title to something like 'Review: Example Co - Senior iOS Engineer' and the systemIntent to 'url.open'. Include a payloadJson object with a valid 'url' field for the role posting.
```

Why this scenario first:

- it exercises the full loop
- it avoids external API dependencies
- it makes result verification obvious

## Real E2E Checklist

## 1. Prepare the iOS app

Open [AgentKVTiOS/GETTING_STARTED.md](../AgentKVTiOS/GETTING_STARTED.md) and launch the iOS app in Xcode.

Verify:

- the app opens successfully
- the Missions tab is visible
- the Actions tab starts empty or shows previous items clearly
- the Log tab opens

## 2. Prepare the Mac Brain as an app

The Mac side should be run as a macOS app target with:

- iCloud capability enabled
- the shared container `iCloud.AgentKVT`
- the shared app group `group.com.agentkvt.shared`
- the entitlements file from [AgentKVTMac/AgentKVTMac.entitlements](../AgentKVTMac/AgentKVTMac.entitlements)

Cross-check with [Docs/SYNC.md](SYNC.md).
Launch reference: [AgentKVTMac/GETTING_STARTED.md](../AgentKVTMac/GETTING_STARTED.md).

Run the Mac app with:

- the shared `AgentKVTMacApp` scheme in Xcode
- `RUN_SCHEDULER=1`
- optional `SCHEDULER_INTERVAL_SECONDS=30` for a tighter verification loop

Verify in the Mac logs:

- the runner starts
- SwiftData storage mode is reported
- the scheduler is polling

## 3. Create the mission on iOS

In the iOS app:

1. Open the Missions tab
2. Create `Tech Job Scout`
3. Paste the prompt above
4. Set a supported schedule
5. Enable `write_action_item`
6. Save

Verify:

- the mission appears in the list
- the schedule format is accepted
- the mission saves without validation errors

## 4. Wait for the mission window

When the mission becomes due, verify on the Mac side:

- the scheduler detects the mission
- the mission runs once
- it does not rerun repeatedly in the same schedule window

Expected Mac-side evidence:

- a `start` log entry
- at least one `tool_call` and `tool_result` log entry for `write_action_item`
- one `outcome` entry

## 5. Verify iOS results

In the iOS app, verify:

- the Actions tab shows a new item
- the row shows the originating mission name
- opening the item detail shows:
  - title
  - intent
  - mission name
  - schedule
  - allowed tools
- the Log tab shows:
  - lifecycle entries under `Outcomes`
  - tool entries under `Tools`
  - readable summaries rather than only raw JSON

## 6. Mark the action done

Open the action detail and tap `Mark Done`.

Verify:

- the action leaves the main unhandled list
- the action state change persists

## Failure Checklist

If the mission does not come through end to end, check these first:

### Mission never appears on Mac

- Mac app is not running with the same CloudKit container
- Mac app is not using the required entitlements
- iOS and Mac are not pointed at the same SwiftData configuration

### Mission appears but never runs

- schedule is malformed or set to a future window
- mission has no allowed tools
- scheduler is running but polling window has not arrived yet

### Mission runs repeatedly

- inspect `lastRunAt` behavior in the shared store
- verify you are on updated scheduler code with idempotent window handling

### Action item is created but not visible on iOS

- shared store is not actually shared
- CloudKit propagation has not completed
- the Mac runner is using fallback storage instead of the intended persistent store

### Logs exist but are not useful

- check the Log tab filters
- inspect whether tool entries are being written with `tool_call` and `tool_result`

## What Was Verified In This Workspace

Within this coding environment, the following were verified directly:

- package tests pass for [ManagerCore](../ManagerCore) and [AgentKVTMac](../AgentKVTMac)
- scheduler idempotency was implemented and covered by tests
- `ActionItem.missionId` propagation was implemented and covered by tests
- richer `AgentLog` event coverage was implemented and covered by tests
- iOS UI now exposes mission-linked action details and more readable log summaries

What was **not** verified in this environment:

- launching the iOS app in Xcode
- running a signed macOS app target with entitlements
- actual CloudKit-backed replication between the two apps

## Fast Local Runner Check

For a runner-only smoke test, you can still use:

```bash
cd AgentKVTMac
swift run AgentKVTMacRunner
```

And for scheduler mode:

```bash
cd AgentKVTMac
RUN_SCHEDULER=1 SCHEDULER_INTERVAL_SECONDS=30 swift run AgentKVTMacRunner
```

Treat this as a local runner validation step, not proof of a true device-to-device E2E loop.
