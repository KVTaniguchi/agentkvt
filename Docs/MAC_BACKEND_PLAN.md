# Mac-Hosted Backend Plan

This document defines the first concrete rollout for moving AgentKVT's shared state off private CloudKit and onto a Rails API + Postgres backend hosted on the server Mac.

## Goal

Make the server Mac the source of truth for shared family data:

- iOS clients connect over a private network from anywhere.
- The Mac agent reads and writes the same canonical mission/action/log data.
- Different Apple IDs are supported because identity is no longer coupled to CloudKit private databases.

## Physical Layout

Repo-managed code:

- Rails API app: `/Users/kevintaniguchi/Development/agentkvt/server`
- Bootstrap scripts: `/Users/kevintaniguchi/Development/agentkvt/bin`
- Overlay templates for the generated Rails app: `/Users/kevintaniguchi/Development/agentkvt/templates/server_overlay`

Mac-local runtime data:

- Postgres data directory: `~/.agentkvt/postgres`
- Postgres logs: `~/.agentkvt/logs/postgres.log`
- Backups: `~/.agentkvt/backups`
- Rails runtime env file: `server/.env`

Important boundary:

- The repo stores migrations, app code, and config templates.
- The actual Postgres table data never lives in Git.

## Network Model

Recommended phase-1 access model:

- `Postgres` listens only on localhost.
- `Rails` listens on the Mac's Tailscale IP.
- iOS clients access the Rails API over Tailscale from outside the local network.
- The Mac agent uses the same Rails API locally.

Why this is the default:

- cheap
- private
- avoids exposing Postgres directly
- avoids public internet hardening in the first rollout

## System of Record

The backend becomes the source of truth for:

- workspaces
- family members
- missions
- life context
- action items
- agent logs

CloudKit can remain optional for purely local Apple UX later, but it is no longer the cross-user sync backbone.

## Phase 1 Schema

### `users`

- `id :uuid`
- `apple_subject :string, null: false, unique`
- `email :string`
- `display_name :string`
- timestamps

### `devices`

- `id :uuid`
- `user_id :uuid, fk`
- `platform :string, null: false`
- `device_name :string`
- `app_version :string`
- `push_token :string`
- `last_seen_at :datetime`
- timestamps

### `workspaces`

- `id :uuid`
- `name :string, null: false`
- `slug :string, null: false, unique`
- `server_mode :string, null: false, default: "single_mac_brain"`
- timestamps

### `workspace_memberships`

- `id :uuid`
- `workspace_id :uuid, fk`
- `user_id :uuid, fk`
- `role :string, null: false, default: "member"`
- `status :string, null: false, default: "active"`
- timestamps

### `family_members`

- `id :uuid`
- `workspace_id :uuid, fk`
- `device_id :uuid, optional fk`
- `display_name :string, null: false`
- `symbol :string`
- `source :string, null: false, default: "ios"`
- timestamps

### `missions`

- `id :uuid`
- `workspace_id :uuid, fk`
- `owner_profile_id :uuid, optional fk -> family_members`
- `source_device_id :uuid, optional fk -> devices`
- `mission_name :string, null: false`
- `system_prompt :text, null: false`
- `trigger_schedule :string, null: false`
- `allowed_mcp_tools :jsonb, null: false, default: []`
- `is_enabled :boolean, null: false, default: true`
- `last_run_at :datetime`
- `source_updated_at :datetime`
- timestamps

### `life_context_entries`

- `id :uuid`
- `workspace_id :uuid, fk`
- `updated_by_user_id :uuid, optional fk -> users`
- `key :string, null: false`
- `value :text, null: false`
- timestamps

### `action_items`

- `id :uuid`
- `workspace_id :uuid, fk`
- `source_mission_id :uuid, optional fk -> missions`
- `owner_profile_id :uuid, optional fk -> family_members`
- `title :string, null: false`
- `system_intent :string, null: false`
- `payload_json :jsonb, null: false, default: {}`
- `relevance_score :float, null: false, default: 0.0`
- `is_handled :boolean, null: false, default: false`
- `handled_at :datetime`
- `timestamp :datetime, null: false`
- `created_by :string, null: false, default: "mac_agent"`
- timestamps

### `agent_logs`

- `id :uuid`
- `workspace_id :uuid, fk`
- `mission_id :uuid, optional fk -> missions`
- `phase :string, null: false`
- `content :text, null: false`
- `metadata_json :jsonb, null: false, default: {}`
- `timestamp :datetime, null: false`
- timestamps

## Phase 1 API Surface

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

## Repo Integration Plan

### iOS

Replace CloudKit-as-bridge with an API client that can:

- fetch bootstrap state
- read and write missions
- read and write family members
- read and write life context
- read action items and logs

### Mac

Introduce storage protocols so the runner no longer directly assumes SwiftData for shared production state:

- `MissionStore`
- `LifeContextStore`
- `ActionItemStore`
- `AgentLogStore`

Implementations:

- `SwiftData*Store` for local/dev compatibility
- `Backend*Store` for Mac production use

## SSH Workflow

Bootstrap once:

```bash
cd /Users/kevintaniguchi/Development/agentkvt
./bin/bootstrap_agentkvt_backend.sh
```

Run the API:

```bash
cd /Users/kevintaniguchi/Development/agentkvt
./bin/run_agentkvt_api.sh
```

Tail logs:

```bash
tail -f ~/.agentkvt/logs/postgres.log
cd /Users/kevintaniguchi/Development/agentkvt/server
tail -f log/development.log
```

## Milestones

### Milestone 1

- Generate Rails API app
- Bring up Postgres on the Mac
- Apply core schema
- Add `/healthz`

### Milestone 2

- Mac agent reads missions from backend
- Mac agent writes action items and agent logs to backend

### Milestone 3

- iOS reads backend missions, action items, and logs
- iOS writes family members, missions, and life context

### Milestone 4

- Add Sign in with Apple
- Add device registration and push hooks

### Milestone 5

- Migrate chat, email summaries, work units, and resource health

## Notes

- The current docs in `Docs/SYNC.md` and `Docs/DATA_FLOW.md` still describe the old CloudKit-first bridge. They should be rewritten once Milestone 1 is standing.
- The backend should be considered the canonical source of truth once the Mac and iOS app both read and write through it.
