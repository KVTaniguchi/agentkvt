# Sync: Bridge Between Mac and iOS

The **Bridge** is shared state between the Brain (macOS) and the Remote (iOS). The macOS app is the writer/processor; the iOS app is the observer/controller.

## Requirement for syncing to work

For syncing to actually work, the two apps must share data in a **shared SwiftData store**. That means a **shared CloudKit container**: both the iOS app and the Mac app use the same CloudKit container identifier so that SwiftData + CloudKit syncs the same schema (ManagerCore) between devices. Without a shared container, each app has its own local store and no data flows between them.

## Family identity model (current direction)

This project now assumes a **single shared family Apple ID** for the AgentKVT system (Mac brain + iOS clients), with **in-app per-person profiles**:

- iCloud auth is handled by iOS/macOS Settings using the family Apple ID.
- AgentKVT does **not** collect Apple ID passwords in-app.
- Each person creates a `FamilyMember` profile in the app.
- User attribution is stored in shared records (for example `ChatMessage.authorProfileId`, `InboundFile.uploadedByProfileId`).
- Per-device active profile selection is local (`UserDefaults`), while `FamilyMember` rows sync through CloudKit.

## CloudKit approach (recommended)

- Use SwiftData's CloudKit integration with one **shared CloudKit container** for both apps.
- **In Xcode:** Enable the **iCloud** capability (CloudKit) on both the iOS and Mac targets, and select the **same** CloudKit container (e.g. `iCloud.com.yourteam.AgentKVT`) for both. Create the container in the Apple Developer portal if needed.
- **In code:** Both apps create a `ModelContainer` with the same `Schema` (ManagerCore) and the same `cloudKitContainerIdentifier` in `ModelConfiguration`. The Mac writes missions, ActionItems, and AgentLog; the iOS app reads and displays them. Sync happens via iCloud.

## Alternative: local network / Tailscale

- Run a shared persistence layer on the Mac and have iOS connect over the local network or Tailscale. Requires custom sync service or shared DB; both apps still need the same schema (ManagerCore). More setup; data stays on your network.

## Production CloudKit note

If the iPhone client is installed through TestFlight, the Mac side should also be distributed in a production-style way instead of being run only from Xcode. See [Docs/MAC_PRODUCTION_DEPLOYMENT.md](MAC_PRODUCTION_DEPLOYMENT.md).

## Enabling the Mac app to use the shared CloudKit container

The Mac side is currently a **Swift Package executable** (`swift run AgentKVTMacRunner`). Executables built with SPM do not get code-signed with entitlements, so they cannot use iCloud/CloudKit. To share the same container as iOS, the Mac must run as an **Xcode-built macOS app** that has the iCloud capability.

### Option A: Add a macOS app target in Xcode

1. **Create a new macOS app target** (or a new Xcode project for Mac) that builds an `.app` bundle.
2. **Add the iCloud capability** to that target:
   - Select the Mac app target → **Signing & Capabilities** → **+ Capability** → **iCloud**.
   - Under **Services**, check **CloudKit** (same as iOS).
   - Under **Containers**, add or select the **same** container as iOS: `iCloud.AgentKVT`. Use the same container for both targets; do not create a second container for Mac.
3. **Attach the entitlements file**: Use `AgentKVTMac/AgentKVTMac.entitlements` (same container and CloudKit service as iOS). In the target’s **Build Settings**, set **Code Signing Entitlements** to that file.
4. **Wire in the runner**: Have the Mac app depend on the AgentKVTMac package (or embed its code) and run the same scheduler/runner logic from the app’s main entry point (e.g. `@main` struct that calls into AgentKVTMacRunner). Ensure the runner uses `ModelConfiguration(..., cloudKitContainerIdentifier: "iCloud.AgentKVT")` when creating the `ModelContainer` so SwiftData uses the shared CloudKit container.
5. **Run the Mac app** from Xcode (or as a signed `.app`) instead of `swift run AgentKVTMacRunner`. For headless/scheduler use, you can run the built app from Terminal or launchd with the same env vars (e.g. `RUN_SCHEDULER=1`).

### Option B: Use the existing entitlements file only

The repo includes `AgentKVTMac/AgentKVTMac.entitlements` with the same iCloud container (`iCloud.AgentKVT`) and CloudKit service as the iOS app. When you create the Mac app target in Xcode, assign this file to the target’s **Code Signing Entitlements** and add the iCloud capability as above; Xcode will keep the capability and entitlements in sync.

### Summary

| Step | iOS (AgentKVTiOS) | Mac (new app target) |
|------|-------------------|------------------------|
| Capability | iCloud → CloudKit ✓ | iCloud → CloudKit ✓ |
| Container | `iCloud.AgentKVT` | **Same:** `iCloud.AgentKVT` |
| ModelConfiguration | `cloudKitContainerIdentifier: "iCloud.AgentKVT"` | Same in runner code when run as app |

## Implementation checklist (CloudKit)

- [ ] Create one CloudKit container in Apple Developer (e.g. `iCloud.AgentKVT` — already used by iOS).
- [ ] Enable iCloud capability + CloudKit on **AgentKVTiOS** and on a **macOS app target** that runs the AgentKVTMac logic; assign the **same** container (`iCloud.AgentKVT`) to both.
- [ ] Both apps use **ManagerCore** and the same schema list, including family/stigmergy models:
  - `LifeContext`, `MissionDefinition`, `ActionItem`, `AgentLog`, `InboundFile`
  - `ChatThread`, `ChatMessage`, `IncomingEmailSummary`
  - `WorkUnit`, `EphemeralPin`, `ResourceHealth`, `FamilyMember`
- [ ] Configure `ModelConfiguration` with the same `cloudKitContainerIdentifier: "iCloud.AgentKVT"` (and optional `allowsSave: true` where needed). See Apple's SwiftData + CloudKit documentation for the exact API.

## Status

**Current direction:** CloudKit-backed shared store with one family Apple ID for AgentKVT devices, plus in-app family profiles (`FamilyMember`) for per-person attribution.
