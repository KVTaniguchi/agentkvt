# AgentKVTiOS (Remote)

SwiftUI iPhone client for the AgentKVT family server. The app reads shared family state from the Rails/Postgres backend and sends mutations back to the server instead of relying on a shared SwiftData store.

## Run the app in the Simulator

**If you don’t see a Run command or the app doesn’t launch:** follow **[GETTING_STARTED.md](GETTING_STARTED.md)**. You must open **`AgentKVTiOS.xcodeproj`** (the project file), choose the **Run iOS App** or **AgentKVTiOS** scheme, pick an **iPhone** simulator as destination, then press **Run** (⌘R).

## Requirements

- Xcode 15+ (iOS 17)
- reachable AgentKVT family server API

## Setup

1. Open `AgentKVTiOS.xcodeproj` in Xcode.
2. Select the **AgentKVTiOS** scheme (top-left, next to the run button).
3. In the **destination** dropdown (next to the scheme), choose an **iPhone Simulator** (e.g. **iPhone 17**, **iPhone 16e**, or **iPhone 15**). If you leave it on **"My Mac (Designed for iPad/iPhone)"**, the app runs in a Mac window and the **iOS Simulator app will not open**—so the simulator “doesn’t show.”
4. Select the AgentKVTiOS target and set your **Development Team** under Signing & Capabilities so the app can build and run.
5. Press **Run** (⌘R). The Simulator app should open and launch the app.

## Features

- **Objectives tab:** Create and manage server-backed objectives. Review plan and follow-up states, monitor live work with `Working On Now` and `Likely next check-in`, inspect research results, and use the `Latest Follow-up` / `Follow-up Loop` flow.
- **Actions tab:** Lists server-backed `ActionItem` entries with native intent buttons (url.open, calendar.create, etc.).
- **Context tab:** Edit server-backed `LifeContext` entries (goals, location, preferences).
- **Log tab:** Review recent family-server agent logs grouped by phase.
- **Chat tab:** Conversational interface with the agent, with family profile attribution.
- **Files tab:** Upload PDFs, text files, or spreadsheets to the family server for agent processing.

For the backend-first sync model, see `Docs/SYNC.md`.

**Build succeeds but nothing launches?** See [RUN_TROUBLESHOOTING.md](RUN_TROUBLESHOOTING.md) (scheme, destination, simulator, and Run settings).
