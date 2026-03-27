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

### Last pushed commit before backend pivot

Latest pushed CloudKit diagnostics commit:

- `d0e85b6` - logs CloudKit account identity diagnostics on iOS and Mac

### Local backend pivot scaffold created but not yet committed

Current local changes:

- modified [`.gitignore`](/Users/kevintaniguchi/Development/agentkvt/.gitignore)
- modified [`README.md`](/Users/kevintaniguchi/Development/agentkvt/README.md)
- new [`MAC_BACKEND_PLAN.md`](/Users/kevintaniguchi/Development/agentkvt/Docs/MAC_BACKEND_PLAN.md)
- new [`bootstrap_agentkvt_backend.sh`](/Users/kevintaniguchi/Development/agentkvt/bin/bootstrap_agentkvt_backend.sh)
- new [`run_agentkvt_api.sh`](/Users/kevintaniguchi/Development/agentkvt/bin/run_agentkvt_api.sh)
- new overlay templates under [`templates/server_overlay`](/Users/kevintaniguchi/Development/agentkvt/templates/server_overlay)

These files define:

- where the Rails app should live in the repo
- how Postgres should be created and started on the server Mac
- the first schema for shared data
- SSH-friendly commands to bootstrap and run the service

### Important unrelated local change

There is also an unrelated local modification that should stay out of backend commits unless intentionally included:

- [ManagerCoreModelTests.swift](/Users/kevintaniguchi/Development/agentkvt/ManagerCore/Tests/ManagerCoreTests/ManagerCoreModelTests.swift)

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

- `POST /v1/auth/apple`
- `GET /v1/bootstrap`
- `GET /v1/family_members`
- `POST /v1/family_members`
- `PATCH /v1/family_members/:id`
- `GET /v1/missions`
- `POST /v1/missions`
- `PATCH /v1/missions/:id`
- `GET /v1/life_context`
- `PUT /v1/life_context/:key`
- `GET /v1/action_items`
- `POST /v1/action_items/:id/handle`
- `GET /v1/agent_logs`

Mac agent-facing:

- `GET /v1/agent/due_missions`
- `POST /v1/agent/missions/:id/action_items`
- `POST /v1/agent/missions/:id/logs`
- `POST /v1/agent/heartbeats`

## What Needs To Happen Next

### 1. Commit the backend scaffold

Commit only the backend pivot files, not unrelated test edits.

Likely files to stage:

- [`.gitignore`](/Users/kevintaniguchi/Development/agentkvt/.gitignore)
- [`README.md`](/Users/kevintaniguchi/Development/agentkvt/README.md)
- [`MAC_BACKEND_PLAN.md`](/Users/kevintaniguchi/Development/agentkvt/Docs/MAC_BACKEND_PLAN.md)
- [`BACKEND_PIVOT_HANDOFF.md`](/Users/kevintaniguchi/Development/agentkvt/Docs/BACKEND_PIVOT_HANDOFF.md)
- [`bootstrap_agentkvt_backend.sh`](/Users/kevintaniguchi/Development/agentkvt/bin/bootstrap_agentkvt_backend.sh)
- [`run_agentkvt_api.sh`](/Users/kevintaniguchi/Development/agentkvt/bin/run_agentkvt_api.sh)
- everything under [`templates/server_overlay`](/Users/kevintaniguchi/Development/agentkvt/templates/server_overlay)

Do not stage:

- [ManagerCoreModelTests.swift](/Users/kevintaniguchi/Development/agentkvt/ManagerCore/Tests/ManagerCoreTests/ManagerCoreModelTests.swift)

### 2. Pull onto the server Mac

On the server Mac:

```bash
cd /Users/familyagent/AgentKVTMac-or-repo-path
git pull origin main
```

Adjust the path to the actual repo location on the server.

### 3. Bootstrap the backend on the server Mac

Run:

```bash
cd /Users/kevintaniguchi/Development/agentkvt
./bin/bootstrap_agentkvt_backend.sh
```

What this should do:

- ensure Homebrew Ruby and PostgreSQL 16 are installed
- initialize `~/.agentkvt/postgres`
- start Postgres
- create development/test/production databases
- generate `server/` as a Rails API app if it does not exist
- overlay the first config and migrations
- run `bundle install`
- run `bin/rails db:prepare`

### 4. Create env file

After bootstrap:

```bash
cd /Users/kevintaniguchi/Development/agentkvt
cp server/.env.example server/.env
```

For phase 1, a placeholder agent token is enough.

### 5. Start the API from SSH

Run:

```bash
cd /Users/kevintaniguchi/Development/agentkvt
./bin/run_agentkvt_api.sh
```

This script:

- ensures Postgres is running
- loads `server/.env` if present
- binds Rails to the Tailscale IP if available, else localhost

### 6. Verify service health

In another shell:

```bash
curl http://127.0.0.1:3000/healthz
```

Or use the Tailscale IP if Rails bound there.

## Suggested Follow-up Implementation Order

### Milestone 1

- get Rails API app booting
- confirm `/healthz`
- confirm DB tables exist

### Milestone 2

- add Rails models
- add `missions`, `action_items`, and `agent_logs` endpoints
- add a simple shared token auth for Mac agent calls

### Milestone 3

- add `APIClient` to iOS
- have iOS fetch missions and action items from Rails
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
