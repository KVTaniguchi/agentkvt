# Sync Decision: Bridge Between Mac and iOS

The **Bridge** is shared state between the Brain (macOS) and the Remote (iOS). The macOS app is the writer/processor; the iOS app is the observer/controller.

## Options

1. **CloudKit**  
   Use SwiftData’s CloudKit integration so that the same schema syncs across devices. Pros: works across networks, no local setup. Cons: requires Apple Developer account, data in iCloud, possible latency.

2. **Local network / Tailscale**  
   Run a shared persistence layer (e.g. a local sync service or shared DB) on the Mac and have iOS connect over the local network or Tailscale. Pros: data stays on your network, low latency. Cons: more setup, iOS and Mac must be on the same network (or reachable via Tailscale).

## Recommendation

- **For development and single-user “same LAN” use:** Prefer **local network or Tailscale** so the Mac is the source of truth and iOS connects to it. Implement by either:
  - Using a sync service that exposes the same SwiftData schema (e.g. custom sync endpoint + NSPersistentCloudKitContainer or equivalent), or
  - Using CloudKit with a private container so both apps share the same container and schema.

- **For simplicity and to avoid custom server code:** Use **SwiftData with CloudKit**. Configure the same CloudKit container and schema on both the Mac and iOS apps; the Mac writes (missions, ActionItems, AgentLog) and the iOS app observes and displays.

## Implementation notes

- Both apps must use **ManagerCore** and the same `Schema([LifeContext.self, MissionDefinition.self, ActionItem.self, AgentLog.self])`.
- ModelContainer configuration should enable CloudKit if that option is chosen (see Apple’s SwiftData + CloudKit documentation).
- If using local sync, the Mac app must run a service that the iOS app can reach (e.g. over HTTPS on the LAN or via Tailscale); schema and entity names must match ManagerCore.

## Status

**Decision:** Deferred. Implement initial version with **local-only SwiftData** (no sync) so both apps can run and the mission engine can write ActionItems. Add CloudKit or local-network sync in a follow-up once the rest of the pipeline is stable.
