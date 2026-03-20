# AgentKVTiOS (Remote)

SwiftUI dashboard for the AgentKVT system. Displays dynamic action items from the Mac agent and provides mission authoring and life context editing.

## Run the app in the Simulator

**If you don’t see a Run command or the app doesn’t launch:** follow **[GETTING_STARTED.md](GETTING_STARTED.md)**. You must open **`AgentKVTiOS.xcodeproj`** (the project file), choose the **Run iOS App** or **AgentKVTiOS** scheme, pick an **iPhone** simulator as destination, then press **Run** (⌘R).

## Requirements

- Xcode 15+ (iOS 17)
- ManagerCore package (../ManagerCore)

## Setup

1. Open `AgentKVTiOS.xcodeproj` in Xcode.
2. Select the **AgentKVTiOS** scheme (top-left, next to the run button).
3. In the **destination** dropdown (next to the scheme), choose an **iPhone Simulator** (e.g. **iPhone 17**, **iPhone 16e**, or **iPhone 15**). If you leave it on **"My Mac (Designed for iPad/iPhone)"**, the app runs in a Mac window and the **iOS Simulator app will not open**—so the simulator “doesn’t show.”
4. Select the AgentKVTiOS target and set your **Development Team** under Signing & Capabilities so the app can build and run.
5. Press **Run** (⌘R). The Simulator app should open and launch the app.

## Features

- **Actions tab:** Lists `ActionItem` entries (dynamic buttons from the Mac). Tap to mark as handled.
- **Missions tab:** Create and edit `MissionDefinition` (name, system prompt, trigger schedule, allowed MCP tools).
- **Context tab:** Edit `LifeContext` (static facts the agent uses: goals, location, dates).

Sync with the Mac (SwiftData/CloudKit or local) must be configured so that missions and action items are shared; see `Docs/SYNC.md`.

**Build succeeds but nothing launches?** See [RUN_TROUBLESHOOTING.md](RUN_TROUBLESHOOTING.md) (scheme, destination, simulator, and Run settings).
