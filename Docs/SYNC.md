# Sync: Backend-First Family State

AgentKVT uses a backend-first sync model. The Rails API and Postgres database on the family server are the source of truth for all shared state. Clients read and write through the API.

## Architecture

- Shared family data lives in Postgres on the family server Mac.
- The iOS app connects to the Rails API; no shared SwiftData store, CloudKit container, or app-group container is required on iOS.
- The Mac runner connects to the same Rails API to fetch work and post results.
- Per-device preferences (e.g. selected family profile) stay local in `UserDefaults`.

## Server-Owned Data

The following entities are owned by the backend and synced to clients via the API:

- `FamilyMember`
- `LifeContext`
- `ActionItem`
- `AgentLog`
- `Objective`
- `ObjectiveFeedback`
- `Task`
- `ResearchSnapshot`
- `ChatThread` / `ChatMessage`
- `InboundFile`

## Device-Local Data

These values remain device-local:

- selected family profile
- draft text that has not been submitted
- transient UI state

## Why Postgres

- One source of truth for family data
- No iCloud sign-in requirement for the iPhone client
- No CloudKit/app-group entitlement coupling between iOS and Mac
- Less stale-cache and reconciliation debugging
- TestFlight behavior is easier to reason about because the app reflects server state directly
- Different Apple IDs can share one workspace

## Operational Model

- The iOS app must be configured with a reachable family-server API base URL.
- A TestFlight build picks up API host changes only after a new archive is uploaded (or via local override xcconfig).
- If the phone is off the family network, the configured host must still be reachable (e.g. via Tailscale).

## Legacy Notes

The Mac runner still has some legacy SwiftData/CloudKit code paths that can operate locally in development or offline scenarios. These are not the primary sync path in production.
