# AgentKVTiOS (Remote)

SwiftUI dashboard for the AgentKVT system. Displays dynamic action items from the Mac agent and provides mission authoring and life context editing.

## Requirements

- Xcode 15+ (iOS 17)
- ManagerCore package (../ManagerCore)

## Setup

1. Open `AgentKVTiOS.xcodeproj` in Xcode.
2. Select the AgentKVTiOS target and set your **Development Team** under Signing & Capabilities so the app can build and run.
3. Build and run on a simulator or device.

## Features

- **Actions tab:** Lists `ActionItem` entries (dynamic buttons from the Mac). Tap to mark as handled.
- **Missions tab:** Create and edit `MissionDefinition` (name, system prompt, trigger schedule, allowed MCP tools).
- **Context tab:** Edit `LifeContext` (static facts the agent uses: goals, location, dates).

Sync with the Mac (SwiftData/CloudKit or local) must be configured so that missions and action items are shared; see `Docs/SYNC.md`.
