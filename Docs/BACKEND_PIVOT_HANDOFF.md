# Backend Pivot Handoff

This document is the handoff plan for the AgentKVT architecture pivot from CloudKit-as-shared-backbone to a Mac-hosted Rails API + Postgres backend.

Use this if the conversation context is lost or a different agent needs to resume.

## Why We Pivoted

The original sync design assumed one shared family Apple ID and used CloudKit private database mirroring as the bridge between iOS and the Mac app.

That is no longer the product requirement.

Current product requirement:

- iOS clients use their own Apple IDs
- the Mac server keeps its own Apple ID
- the Mac must not have visibility into each client’s private iCloud database
- all clients still need to share missions, context, actions, and logs with the Mac agent

This makes CloudKit private database sync the wrong transport.

We verified this with native diagnostics:

- iPad user record ID: `_05d67d9df123c28486e2dd172ba27a23`
- Mac user record ID: `_0fdef211f4b2c3d0023fc84472f603c1`

These were logged from:

- [AgentKVTiOSApp.swift](/Users/kevintaniguchi/Development/agentkvt/AgentKVTiOS/AgentKVTiOSApp.swift)
- [RunnerEntryPoint.swift](/Users/kevintaniguchi/Development/agentkvt/AgentKVTMac/Sources/AgentKVTMac/RunnerEntryPoint.swift)

Conclusion:

- CloudKit private sync is working as designed
- it is just the wrong architecture for cross-account server-style sharing

## New Target Architecture

The server Mac becomes the source of truth.

Topology:

- iOS clients -> Rails API on the server Mac
- Mac agent -> same Rails API on the server Mac
- Rails API -> Postgres on the same server Mac

Security and exposure model:

- Postgres stays local-only on the Mac
- Rails binds to localhost or the Mac’s Tailscale IP
- iOS clients access the Rails API over Tailscale from outside the local network

Why this is the chosen path:

- supports different Apple IDs cleanly
- cheap
- private
- operationally simple for a single always-on Mac
- better fit for “server brain” than peer-device CloudKit sharing

## What Is Already Done

### Backend pivot commits already pushed

- `b0b23a7` - add Mac-hosted backend bootstrap plan
- `a299bcc` - add generated Rails API app
- `8f6db62` - add first backend API resources
- `39fe2b5` - wire Mac runner to backend mission API
- `02d9b7a` - wire iOS mission sync to backend API
- `7634c2f` - configure iOS dev backend access

Earlier CloudKit diagnostics work is still useful context:

- `d0e85b6` - logs CloudKit account identity diagnostics on iOS and Mac

### What is fully standing now

Backend foundation:

- Rails API app exists in [`server/`](/Users/kevintaniguchi/Development/agentkvt/server)
- Postgres-backed schema exists for:
  - workspaces
  - family members
  - missions
  - life context entries
  - action items
  - agent logs
- `/healthz` is live
- initial `v1` API resources exist
- backend integration tests were added for the first API slice

Mac runner:

- backend client exists in [BackendAPIClient.swift](/Users/kevintaniguchi/Development/agentkvt/AgentKVTMac/Sources/AgentKVTMac/BackendAPIClient.swift)
- scheduler can fetch `GET /v1/agent/due_missions`
- mission logs and `write_action_item` can post back to Rails
- runner config supports:
  - `AGENTKVT_API_BASE_URL`
  - `AGENTKVT_WORKSPACE_SLUG`
  - `AGENTKVT_AGENT_TOKEN`

iOS app:

- backend bootstrap/sync client exists in [IOSBackendAPIClient.swift](/Users/kevintaniguchi/Development/agentkvt/AgentKVTiOS/Services/IOSBackendAPIClient.swift)
- iOS can now:
  - bootstrap family members and missions from Rails
  - create family members against Rails
  - create, update, and delete missions against Rails
  - mirror backend mission state into local SwiftData
- dev iOS scheme is preconfigured to hit the server Mac at `http://192.168.4.144:3000`
- debug iOS build has a dedicated [Info.Debug.plist](/Users/kevintaniguchi/Development/agentkvt/AgentKVTiOS/Info.Debug.plist) that allows plain HTTP during development

Server Mac runtime config:

- `server/.env` now contains a real `AGENTKVT_AGENT_TOKEN`
- `server/.env` now contains `BIND_IP=0.0.0.0`
- Rails health check succeeded on `http://127.0.0.1:3000/healthz`
- Rails is listening on `*:3000`
- runner plist now exists at:
  - `~/Library/Group Containers/group.com.agentkvt.shared/Library/Application Support/agentkvt-runner.plist`
- runner plist is configured with:
  - `AGENTKVT_API_BASE_URL=http://127.0.0.1:3000`
  - `AGENTKVT_WORKSPACE_SLUG=default`
  - `AGENTKVT_AGENT_TOKEN=<same token as server/.env>`

## Current Intended File Layout

Repo-managed code:

- Rails app root: `/Users/kevintaniguchi/Development/agentkvt/server`
- setup scripts: `/Users/kevintaniguchi/Development/agentkvt/bin`
- template overlay: `/Users/kevintaniguchi/Development/agentkvt/templates/server_overlay`

Mac-local runtime data:

- Postgres data dir: `~/.agentkvt/postgres`
- Postgres log: `~/.agentkvt/logs/postgres.log`
- backups: `~/.agentkvt/backups`
- Rails env file: `server/.env`

Important rule:

- the database files do not belong in Git
- migrations and app code do belong in Git

## First Backend Scope

Phase 1 shared entities:

- `users`
- `devices`
- `workspaces`
- `workspace_memberships`
- `family_members`
- `missions`
- `life_context_entries`
- `action_items`
- `agent_logs`

The first migration template already exists here:

- [20260327001000_create_agentkvt_core_tables.rb](/Users/kevintaniguchi/Development/agentkvt/templates/server_overlay/db/migrate/20260327001000_create_agentkvt_core_tables.rb)

## First API Surface

User-facing:

- `GET /v1/bootstrap`
- `GET /v1/family_members`
- `POST /v1/family_members`
- `GET /v1/missions`
- `POST /v1/missions`
- `PATCH /v1/missions/:id`
- `DELETE /v1/missions/:id`
- `GET /v1/action_items`
- `POST /v1/action_items/:id/handle`
- `GET /v1/agent_logs`

Mac agent-facing:

- `GET /v1/agent/due_missions`
- `POST /v1/agent/missions/:id/action_items`
- `POST /v1/agent/missions/:id/logs`

Planned but not yet implemented:

- `POST /v1/auth/apple`
- `PATCH /v1/family_members/:id`
- `GET /v1/life_context`
- `PUT /v1/life_context/:key`
- `POST /v1/agent/heartbeats`

## Suggested Follow-up Implementation Order

### Immediate next smoke test

1. Relaunch `AgentKVTMacApp` on the server Mac so it reloads the runner plist.
2. Run the iOS app from Xcode on a physical iPad or iPhone.
3. Create or edit a mission and tap `Save`.
4. Verify in the Rails log that the mission mutation hit the backend.
5. Verify in the Mac runtime log that the runner fetched missions from Rails.
6. Set a due schedule and confirm the Mac agent executes it and writes logs/action items back.

### Immediate next product work

- add iOS reads for `action_items`, `agent_logs`, and `life_context`
- add iOS writes for `life_context`
- add a simple workspace bootstrap/seed flow if needed
- verify Mac agent end-to-end against Ollama with one real due mission

### Outside-network rollout work

- choose the transport:
  - Tailscale, or
  - HTTPS/public reverse proxy
- stop relying on the LAN IP `192.168.4.144`
- add a production config/discovery story for iOS clients
- add real user auth:
  - Sign in with Apple
  - app-issued session token

### Cleanup and hardening

- rewrite old CloudKit-centric docs in `Docs/SYNC.md` and `Docs/DATA_FLOW.md`
- decide whether Mac production should use only backend mode for shared data
- add better server observability around mission execution and API errors
- have iOS write missions to Rails

### Milestone 4

- add backend store abstraction on Mac
- make Mac scheduler fetch due missions from Rails
- make Mac write action items and logs to Rails

### Milestone 5

- add Sign in with Apple
- map Apple identity to backend `users`
- add workspace membership and per-family data ownership

### Milestone 6

- move remaining shared entities off CloudKit
- chat
- email summaries
- work units
- resource health

## Architectural Decisions To Preserve

- The Mac-hosted backend is the canonical shared store.
- Postgres must not be internet-exposed.
- Rails API is the only externally reachable component.
- Tailscale is the default outside-network access layer.
- CloudKit should not remain the required cross-user transport.
- Apple identity can still be used for login, but not for storage topology.

## Useful Files For The Next Agent

Architecture decision:

- [MAC_BACKEND_PLAN.md](/Users/kevintaniguchi/Development/agentkvt/Docs/MAC_BACKEND_PLAN.md)

Bootstrap scripts:

- [bootstrap_agentkvt_backend.sh](/Users/kevintaniguchi/Development/agentkvt/bin/bootstrap_agentkvt_backend.sh)
- [run_agentkvt_api.sh](/Users/kevintaniguchi/Development/agentkvt/bin/run_agentkvt_api.sh)

Template files:

- [database.yml](/Users/kevintaniguchi/Development/agentkvt/templates/server_overlay/config/database.yml)
- [routes.rb](/Users/kevintaniguchi/Development/agentkvt/templates/server_overlay/config/routes.rb)
- [health_controller.rb](/Users/kevintaniguchi/Development/agentkvt/templates/server_overlay/app/controllers/health_controller.rb)
- [create_agentkvt_core_tables.rb](/Users/kevintaniguchi/Development/agentkvt/templates/server_overlay/db/migrate/20260327001000_create_agentkvt_core_tables.rb)

Old CloudKit assumptions that will need rewriting later:

- [SYNC.md](/Users/kevintaniguchi/Development/agentkvt/Docs/SYNC.md)
- [DATA_FLOW.md](/Users/kevintaniguchi/Development/agentkvt/Docs/DATA_FLOW.md)

## Open Questions

- Do iOS clients all run Tailscale, or do we later need public HTTPS?
- Should the Mac agent call Rails over HTTP locally, or should it get a direct server-side persistence adapter later?
- How much offline capability should iOS retain if Rails is unreachable?
- Should SwiftData remain as a local cache on iOS, or should phase 1 use backend-only reads/writes for simplicity?

## Handoff Summary

The pivot decision is made.

Do not keep trying to force cross-account sync through CloudKit private databases.

The next agent should:

1. commit the backend scaffold
2. pull it to the server Mac
3. run the bootstrap script
4. bring up Rails and Postgres
5. verify `/healthz`
6. start implementing phase-1 Rails models and endpoints
