# AgentKVT Rails API

Rails API backend for the AgentKVT system. Runs on the family server Mac backed by a local PostgreSQL database. Serves as the system of record for objectives, tasks, research snapshots, action items, agent logs, family members, life context, chat, and inbound files.

## Quick Start

```bash
cd server
bundle install
bin/rails db:create db:migrate
bin/rails server -p 3000
```

Verify: `curl -sS http://127.0.0.1:3000/healthz`

## Key Components

### Models
- **Objective** — User-defined goals that the system decomposes into tasks.
- **ObjectiveDraft / ObjectiveDraftMessage** — Ephemeral guided-authoring sessions for objective composition before final creation.
- **Task** — Concrete research/synthesis steps within an objective. Dispatched to Mac agents via webhooks.
- **ResearchSnapshot** — Persisted findings from agent research, linked to objectives.
- **ActionItem** — Dynamic buttons for the iOS dashboard (agent writes, user acts).
- **AgentLog** — Append-only audit trail of agent execution.
- **Workspace** — Isolation boundary; clients scope requests via `X-Workspace-Slug` header.
- **FamilyMember** — In-app identity for family attribution.
- **LifeContextEntry** — Static facts and user preferences.
- **ChatThread / ChatMessage** — Conversational interface between user and agent.
- **InboundFile** — Uploaded files waiting for agent processing.

### Services
- **ObjectiveComposer** — Direct Rails-to-Ollama drafting loop for interactive objective composition and follow-up questions.
- **ObjectivePlanner** — LLM-assisted task decomposition. Builds planner input from the objective goal plus any structured brief metadata before persisting tasks.
- **ObjectivePlanningInputBuilder** — Normalizes `goal`, `objective_kind`, and `brief_json` into the planner-facing prompt payload.
- **ObjectiveKickoff** — Shared activation path that enqueues planning when an objective becomes active.
- **ObjectivePresentationBuilder** — Generates structured UI layouts from research snapshots for iOS generative results views.
- **MacAgentClient** — Dispatches task webhooks to registered Mac agents.

### Jobs
- **ObjectivePlannerJob** — Background job that decomposes an objective into tasks.
- **TaskExecutorJob** — Background job that dispatches a task to a Mac agent via webhook.

## API Surface

### Client Endpoints (iOS)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/v1/bootstrap` | Bootstrap snapshot (family, context, logs, actions) |
| GET/POST | `/v1/objectives` | List / create objectives |
| GET/PUT/DELETE | `/v1/objectives/:id` | Show / update / destroy objective |
| POST | `/v1/objectives/:id/run_now` | Trigger immediate execution |
| POST | `/v1/objectives/:id/rerun` | Reset and re-execute |
| POST | `/v1/objectives/:id/reset_stuck_tasks_and_run` | Reset stuck tasks |
| POST | `/v1/objective_drafts` | Start a guided objective draft session |
| GET | `/v1/objective_drafts/:id` | Resume a guided objective draft |
| POST | `/v1/objective_drafts/:id/messages` | Submit a drafting turn and receive the next assistant response |
| POST | `/v1/objective_drafts/:id/finalize` | Create the real objective from the draft snapshot |
| GET | `/v1/objectives/:id/presentation` | Generative results layout |
| GET | `/v1/action_items` | List action items |
| POST | `/v1/action_items/:id/handle` | Mark action as handled |
| GET | `/v1/agent_logs` | List agent logs |
| POST | `/v1/chat_wake` | Wake the agent for chat |

### Agent Endpoints (Mac Brain)

| Method | Path | Description |
|--------|------|-------------|
| GET | `/v1/agent/chat_wake` | Long-poll for chat wake events |
| POST | `/v1/agent/logs` | Create agent log entries |
| POST | `/v1/agent/register` | Register agent capabilities |
| POST | `/v1/agent/chat_messages/claim_next` | Claim next pending chat message |
| POST/GET | `/v1/agent/objectives/:id/research_snapshots` | Create / list snapshots |

## Authentication

- Agent endpoints use bearer token auth via `AGENTKVT_AGENT_TOKEN` env var.
- Client endpoints use workspace scoping via `X-Workspace-Slug` header.

## Deployment

See [Docs/DEPLOYMENT.md](../Docs/DEPLOYMENT.md) for full production deployment instructions.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `RAILS_ENV` | `development` or `production` |
| `SECRET_KEY_BASE` | Rails secret key |
| `AGENTKVT_AGENT_TOKEN` | Bearer token for agent endpoints |
| `AGENTKVT_ALLOW_HTTP` | Set to `1` for HTTP (Tailscale/LAN) |
| `AGENTKVT_BIND_ALL_INTERFACES` | Set to `1` to bind `0.0.0.0` |
| `OLLAMA_HOST` | Ollama base URL for ObjectivePlanner |
| `OLLAMA_MODEL` | Default Ollama model used by planner and composer |
| `OBJECTIVE_COMPOSER_MODEL` | Optional Ollama model override for guided objective drafting |
