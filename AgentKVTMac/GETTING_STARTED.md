# Run the Mac Brain in Xcode

Use this guide when you want to run the AgentKVT Mac Brain as a signed macOS app instead of a plain `swift run` executable. This is the preferred path for real shared-store and CloudKit verification.

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
- the CloudKit container `iCloud.AgentKVT`
- the application group `group.com.agentkvt.shared`

If Xcode asks you to resolve signing or capability issues, fix those before relying on the app for sync verification.

## 5. Run the app

Press `Run` in Xcode.

Expected behavior:

- the Mac app launches as a minimal app wrapper
- the scheduler starts automatically
- console output includes the selected SwiftData storage mode
- the runner begins polling for due missions

## 6. Use this for real E2E verification

This is the path to use when following:

- [Docs/E2E_VERIFICATION.md](../Docs/E2E_VERIFICATION.md)
- [Docs/SYNC.md](../Docs/SYNC.md)

Why:

- `swift run AgentKVTMacRunner` is still useful for local runner checks
- but the Xcode-built Mac app is the right path for signed entitlements, shared-store behavior, and realistic iOS-to-Mac verification
