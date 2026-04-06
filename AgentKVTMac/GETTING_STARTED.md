# Run the Mac Brain in Xcode

Use this guide when you want to run the AgentKVT Mac Brain as a signed macOS app. For backend mode (recommended), the app connects to the Rails API on the same Mac.

## 1. Open the existing Xcode project

Open:

- [AgentKVTiOS/AgentKVTiOS.xcodeproj](../AgentKVTiOS/AgentKVTiOS.xcodeproj)

The Mac app target lives inside this project.

## 2. Choose the Mac scheme

In the Xcode scheme picker, choose:

- `AgentKVTMacApp`

This shared scheme is configured to launch the Mac Brain with:

- `RUN_SCHEDULER=1`
- `SCHEDULER_INTERVAL_SECONDS=30`

You can edit the scheme later if you want different values.

## 3. Choose a Mac destination

Set the run destination to:

- `My Mac`

Do not use an iPhone simulator for this scheme.

## 4. Confirm signing and capabilities

The Mac target should use:

- the entitlements file [AgentKVTMac/AgentKVTMac.entitlements](AgentKVTMac.entitlements)

If Xcode asks you to resolve signing or capability issues, fix those before running.

## 5. Run the app

Press `Run` in Xcode.

Expected behavior:

- the Mac app launches as a minimal app wrapper
- the scheduler starts automatically
- console output includes the selected SwiftData storage mode
- the runner begins polling for due missions

## 6. Configuration

For backend mode (recommended), configure the runner plist with API connection details. See [Docs/DEPLOYMENT.md](../Docs/DEPLOYMENT.md) for full configuration.

For local-only development, `swift run AgentKVTMacRunner` can be used for isolated runner checks without the backend.
