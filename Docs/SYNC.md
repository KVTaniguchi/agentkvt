# Sync: Backend-First Family State

AgentKVT is moving to a backend-first sync model.

For shared family data, the Rails API and Postgres database on the family server are the source of truth. The iOS client should behave like a thin remote client: fetch shared state from the server, send mutations back to the server, and avoid maintaining a second persisted database on-device.

## Current Direction

- Shared family data lives on the family server.
- The iOS app no longer depends on a shared SwiftData store, CloudKit container, or app-group container for startup.
- Per-device preferences such as the selected family profile can stay local in lightweight storage such as `UserDefaults`.
- The Mac runner still has some legacy SwiftData/CloudKit paths and should be migrated in a follow-up phase.

## iOS Data Ownership

These flows should be server-owned:

- `FamilyMember`
- `LifeContext`
- `ActionItem`
- `AgentLog`
- `Objective`
- `Task`
- `ResearchSnapshot`

These flows are still in migration and should move to the family server next:

- chat threads and messages
- inbound files
- objective work-unit / board state

These values can remain device-local:

- selected family profile
- draft text that has not been submitted
- transient UI state

## Why We Are Favoring Postgres

- one source of truth for family data
- no iCloud sign-in requirement for the iPhone client
- no CloudKit/app-group entitlement coupling between iOS and Mac
- less stale-cache and reconciliation debugging
- TestFlight behavior is easier to reason about because the app reflects server state directly

## Operational Model

- The iOS app must be configured with a reachable family-server API base URL.
- A TestFlight build only picks up API host changes after a new archive is uploaded.
- If the phone is off the family network, the configured host must still be reachable from that network path.

## Migration Status

Completed on iOS:

- backend bootstrap for family members, life context, action items, agent logs, and objectives
- removal of the shared SwiftData model container from app startup
- removal of iCloud and app-group entitlements from the iOS target
- replacement of local chat and inbound-file persistence with explicit migration placeholders

Still pending:

- server endpoints for chat, inbound files, and any remaining worker-board state the iPhone needs
- Mac runner migration away from legacy SwiftData/CloudKit dependencies

## Recommended Sequence

1. Keep Postgres/Rails as the canonical shared family database.
2. Finish the remaining server endpoints needed by iOS.
3. Remove any remaining iOS features that still assume local persisted shared models.
4. Migrate the Mac runner off the old CloudKit/shared-SwiftData bridge.

This sequence keeps the phone simple first, which makes TestFlight validation and production debugging much easier.
