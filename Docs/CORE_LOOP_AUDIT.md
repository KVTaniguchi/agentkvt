# Core Loop Audit

This document audits roadmap item 1: the end-to-end path from mission authoring on iOS to mission execution on macOS to `ActionItem` display back on iOS.

Audit date: 2026-03-19

## Goal

Confirm whether the current codebase supports the intended closed loop:

1. create a mission on iPhone
2. let the Mac runner pick it up on schedule
3. execute the mission with an allowed tool set
4. write `ActionItem` and `AgentLog` records
5. observe those records in the iOS app

## What Was Verified

### Code path exists

The major pieces for the loop are present:

- iOS mission authoring exists in [AgentKVTiOS/Views/MissionListView.swift](../AgentKVTiOS/Views/MissionListView.swift)
- iOS action display exists in [AgentKVTiOS/Views/DashboardView.swift](../AgentKVTiOS/Views/DashboardView.swift)
- iOS log display exists in [AgentKVTiOS/Views/AgentLogView.swift](../AgentKVTiOS/Views/AgentLogView.swift)
- macOS scheduler exists in [AgentKVTMac/Sources/AgentKVTMac/MissionScheduler.swift](../AgentKVTMac/Sources/AgentKVTMac/MissionScheduler.swift)
- macOS mission execution exists in [AgentKVTMac/Sources/AgentKVTMac/MissionRunner.swift](../AgentKVTMac/Sources/AgentKVTMac/MissionRunner.swift)
- `write_action_item` exists in [AgentKVTMac/Sources/AgentKVTMac/WriteActionItemTool.swift](../AgentKVTMac/Sources/AgentKVTMac/WriteActionItemTool.swift)

### Automated tests pass

The package tests currently pass:

- `cd ManagerCore && swift test`
- `cd AgentKVTMac && swift test`

This gives confidence that individual components and mocked mission runs are functional.

## Current End-to-End Story

### 1. Mission creation on iOS

The iOS app can create and save `MissionDefinition` records with:

- mission name
- system prompt
- trigger schedule
- allowed tool IDs

Source: [AgentKVTiOS/Views/MissionListView.swift](../AgentKVTiOS/Views/MissionListView.swift)

### 2. Shared store bootstrapping

The iOS app uses a SwiftData container configured with:

- app group `group.com.agentkvt.shared`
- CloudKit private database `iCloud.AgentKVT` on device
- no CloudKit in simulator
- in-memory fallback on failure

Source: [AgentKVTiOS/AgentKVTiOSApp.swift](../AgentKVTiOS/AgentKVTiOSApp.swift)

The macOS runner uses a SwiftData container configured with:

- no app group container
- CloudKit private database `iCloud.AgentKVT`
- in-memory fallback on failure

Source: [AgentKVTMac/Sources/AgentKVTMac/RunnerEntryPoint.swift](../AgentKVTMac/Sources/AgentKVTMac/RunnerEntryPoint.swift)

### 3. Mission pickup on macOS

The scheduler fetches all `MissionDefinition` records, filters them through `MissionScheduler`, and runs due missions through `MissionRunner`.

Source: [AgentKVTMac/Sources/AgentKVTMac/RunnerEntryPoint.swift](../AgentKVTMac/Sources/AgentKVTMac/RunnerEntryPoint.swift)

### 4. Mission execution

`MissionRunner` passes the mission prompt and allowed tool IDs into `AgentLoop`, which can call allowed tools and then writes a final `AgentLog` outcome entry.

Source: [AgentKVTMac/Sources/AgentKVTMac/MissionRunner.swift](../AgentKVTMac/Sources/AgentKVTMac/MissionRunner.swift)

### 5. Action display on iOS

The dashboard observes `ActionItem` records and renders unhandled items as tappable rows.

Source: [AgentKVTiOS/Views/DashboardView.swift](../AgentKVTiOS/Views/DashboardView.swift)

## Assessment

The vertical slice is real, but the loop is not yet trustworthy enough to call fully validated end to end.

### Status

- `Present`: mission authoring UI
- `Present`: scheduler and runner
- `Present`: `ActionItem` writing and display
- `Present`: final outcome logging
- `Partial`: shared-store reliability between iOS and macOS
- `Partial`: schedule semantics for repeated real-world runs
- `Partial`: mission traceability from `ActionItem` back to the originating mission
- `Partial`: validation that authored missions are runnable and meaningful

## Gaps Found

### 1. Shared-store configuration is not aligned enough for a clean local E2E story

The iOS app uses an app-group-backed container, but the macOS runner does not. Both also attempt CloudKit.

That means the core loop appears to depend on CloudKit propagation rather than a clearly shared local store, and the simulator path explicitly disables CloudKit. On failure, either side can fall back to in-memory storage, which would silently break the loop while keeping each side individually functional.

Relevant code:

- [AgentKVTiOS/AgentKVTiOSApp.swift](../AgentKVTiOS/AgentKVTiOSApp.swift)
- [AgentKVTMac/Sources/AgentKVTMac/RunnerEntryPoint.swift](../AgentKVTMac/Sources/AgentKVTMac/RunnerEntryPoint.swift)

Why this matters:

- a mission may save successfully on iOS but never become visible to the Mac runner
- an `ActionItem` may be created on Mac but never appear on iPhone
- local testing can pass visually while the actual bridge is fragmented

### 2. Scheduler semantics are too weak for reliable repeated runs

`MissionScheduler` has no last-run tracking.

- `daily|HH:mm` is due only when hour and minute match exactly
- `weekly|weekday` is due for the entire matching weekday

Relevant code:

- [AgentKVTMac/Sources/AgentKVTMac/MissionScheduler.swift](../AgentKVTMac/Sources/AgentKVTMac/MissionScheduler.swift)
- [AgentKVTMac/Sources/AgentKVTMac/RunnerEntryPoint.swift](../AgentKVTMac/Sources/AgentKVTMac/RunnerEntryPoint.swift)

Why this matters:

- a weekly mission can run on every poll for the entire day
- a daily mission can be skipped if the poll interval misses the exact minute
- the current scheduler behavior is not yet safe for dependable automation

### 3. Mission authoring accepts invalid or low-quality definitions too easily

The iOS editor saves any mission with a non-empty name. It does not validate:

- empty system prompts
- malformed schedules
- zero selected tools

Relevant code:

- [AgentKVTiOS/Views/MissionListView.swift](../AgentKVTiOS/Views/MissionListView.swift)

Why this matters:

- the UI can create missions that appear valid but never run
- the user has no feedback when a schedule format is unsupported
- a mission can run without the tools needed to produce an `ActionItem`

### 4. `ActionItem` records are not tied back to the mission that created them

`ActionItem` has a `missionId` field, but `write_action_item` does not populate it.

Relevant code:

- [ManagerCore/Sources/ManagerCore/ActionItem.swift](../ManagerCore/Sources/ManagerCore/ActionItem.swift)
- [AgentKVTMac/Sources/AgentKVTMac/WriteActionItemTool.swift](../AgentKVTMac/Sources/AgentKVTMac/WriteActionItemTool.swift)

Why this matters:

- the iOS app cannot easily show which mission created which action
- audit and debugging become weaker
- mission usefulness is harder to evaluate over time

### 5. Logging proves completion, but not enough of the path

`MissionRunner` writes only the final outcome log entry by default.

Relevant code:

- [AgentKVTMac/Sources/AgentKVTMac/MissionRunner.swift](../AgentKVTMac/Sources/AgentKVTMac/MissionRunner.swift)

Why this matters:

- failures inside the run are harder to diagnose
- it is difficult to explain why an action was created
- the iOS log view is only as useful as the underlying event detail

## Recommended Next Implementation Checklist

To make the core loop genuinely testable and trustworthy, the next steps should be:

1. Unify the shared-store story between iOS and macOS so both apps either use the same local/app-group strategy or the same explicitly supported CloudKit path.
2. Add mission-run state so schedules are evaluated idempotently instead of re-running indefinitely or missing runs.
3. Validate mission authoring inputs on iOS and constrain schedules to supported formats.
4. Propagate mission identity into created `ActionItem` records.
5. Expand `AgentLog` coverage to include mission start, tool usage, and failure details.

## Practical Conclusion

AgentKVT already has enough implementation to demonstrate the shape of the closed loop. What it does not yet have is a fully trustworthy bridge and execution contract for repeated, real-world use.

The best follow-up after this audit is to tackle the bridge and scheduling issues first, because those are the two biggest blockers to proving that a mission authored on iOS can reliably come back as a meaningful `ActionItem`.
