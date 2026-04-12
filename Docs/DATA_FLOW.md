# AgentKVT Data Flow: iOS → Server → Mac Agent → Back to iOS

This document describes how data moves from the moment a user creates an objective in the iOS app through the Rails backend, Mac agent execution, and back to the iOS app as research results, follow-up plans, actions, and logs.

## Architecture

- **Rails API + Postgres** is the system of record for all shared data.
- **iOS** reads and writes objectives, actions, logs, and context through the API.
- **Mac Brain** polls the API for work, runs local LLM inference, and posts results back.
- There is no shared iCloud account requirement. Sync is application-level via the Rails API.

---

## 1. Diagram Overview

```text
[ USER ]
    |
    v
+------------------+       HTTP (JSON)        +------------------------+
|  iOS App         | -----------------------> |  Rails API (:3000)     |
|  SwiftUI +       |       Tailscale/LAN      |  (server/)             |
|  Backend API     | <----------------------- |                        |
+------------------+                         +------------+-------------+
                                                      |
                                                      | Active Record
                                                      v
                                           +------------------------+
                                           |  PostgreSQL            |
                                           |  (objectives, tasks,   |
                                           |   snapshots, actions,  |
                                           |   logs, context, …)    |
                                           +------------------------+
                                                      ^
                                                      |
+------------------+       HTTP (agent token)         |
|  Mac Brain       | --------------------------------+
|  AgentTaskRunner |
|  + Ollama LLM    |       Local IPC
|  + Tool Registry | <------> LLM inference
+------------------+
```

---

## 2. Step-by-Step Flow

### Step 1: User creates an Objective on iOS

**Where:** iOS app → **Objectives** tab → tap **+**.

**What happens:**

- User enters a goal (e.g. "Plan San Diego trip logistics") and taps Save.
- iOS calls `POST /v1/objectives` on the Rails API.
- Rails creates the Objective in Postgres.
- If the objective is marked "active", Rails enqueues `ObjectivePlannerJob`.

---

### Step 2: Rails decomposes the objective into Tasks

**Where:** Server-side background job.

**What happens:**

- `ObjectivePlanner` sends the objective goal to Ollama and asks it to break it down into concrete research tasks.
- Each task is persisted as a `Task` row linked to the objective.
- For each task, Rails enqueues `TaskExecutorJob`, which POSTs a webhook to the Mac agent.

---

### Step 3: Mac agent receives task webhooks

**Where:** Mac Brain — event-driven scheduler.

**What happens:**

- The Mac runner listens for webhook POSTs on a configurable port.
- When a `run_task_search` webhook arrives, the `AgentExecutionQueue` routes it to the `ObjectiveExecutionPool`.
- The pool supervises concurrent workers (bounded concurrency) that each run an `AgentTaskRunner`.

---

### Step 4: AgentTaskRunner researches one task

**Where:** Mac Brain — one LLM conversation per task.

**What happens:**

1. The runner builds a system prompt including the task description, parent objective goal, and tool guidance.
2. It sends the prompt to Ollama with the task's allowed tools.
3. The LLM calls tools (e.g. `multi_step_search`, `web_search_and_fetch`) to gather information.
4. After research, the LLM calls `write_objective_snapshot` to persist findings as a ResearchSnapshot via the Rails API.
5. The runner calls `write_action_item` if there are concrete actions to surface.
6. AgentLog entries are posted to Rails at each phase (start, tool_call, tool_result, outcome).

---

### Step 5: Results flow back to iOS

**Where:** iOS app — Objective Detail, Research, Actions, and Log tabs/views.

**What happens:**

- **Objective Detail:** User taps an objective to see its tasks, research snapshots, follow-up history, and the current execution state. The top `Activity` section answers what the user should do next. If work is active, it can show `No action needed right now`, `Working On Now`, `Recently Finished`, and a `Likely next check-in` estimate derived from recent task pace.
- **Research screen:** User can open the generative results view (server-rendered UI layout) and see `Latest Follow-up`, `Agent Activity`, `Follow-up Loop`, and finding-specific follow-up entry points.
- **Actions tab:** Lists `ActionItem` entries created by the agent. Each is a tappable button (e.g. "Review hotel comparison", intent `url.open`).
- **Log tab:** Shows `AgentLog` entries grouped by phase, so the user can audit what the agent did.
- **Chat tab:** User can have conversational follow-ups with the agent via the chat interface.

### Step 5b: Follow-up feedback becomes the next pass

**Where:** iOS app → Rails API → ObjectiveFeedback planner/lifecycle → Mac Brain.

**What happens:**

1. User submits follow-up feedback from the inline `Continue Research` section in Objective Detail or from the `Continue Research` sheet in the Research screen.
2. Rails persists an `ObjectiveFeedback` record anchored to the whole objective, a task, or a specific finding.
3. `ObjectiveFeedbackPlanner` creates 1-3 linked follow-up tasks with `source_feedback_id`.
4. `ObjectiveFeedbackLifecycle` updates the feedback state to:
   - `review_required` if the next pass is still proposed
   - `planned` if the objective is pending and the batch is approved/saved for later
   - `queued` if the objective is active and the batch is ready for the Mac agent
   - `completed` or `failed` after the linked tasks finish
5. If the objective is active and the next pass is approved, `ObjectiveKickoff` dispatches the new work.
6. iOS keeps the feedback visible as `Latest Follow-up` and in the `Follow-up Loop`, so the user can see what their input changed.

---

## 3. Tools (what runs on the Mac)

| Tool ID | What it does | Writes to server? |
|--------|----------------|------------------|
| **write_action_item** | Creates one ActionItem (title, systemIntent, payload). | Yes → ActionItem |
| **write_objective_snapshot** | Persists research findings for an objective task. | Yes → ResearchSnapshot |
| **read_objective_snapshot** | Reads existing snapshots for an objective/task. | No |
| **web_search_and_fetch** | Ollama web search + page fetch; returns clean Markdown. | No |
| **multi_step_search** | Runs 2–5 related queries in one turn. | No |
| **headless_browser_scout** | Loads URL in headless WebKit; click/fill actions; returns text. | No |
| **send_notification_email** | Sends email to fixed user address. | No |
| **fetch_bee_ai_context** | Fetches personal context from Bee API. | Yes → AgentLog |
| **incoming_email_trigger** | Returns next pending email from Agent Inbox. | No |
| **github_agent** | Read-only GitHub operations. | No |
| **get_life_context** | Reads LifeContext entries from local SwiftData. | No |
| **fetch_agent_logs** | Reads recent agent logs (from backend or local). | No |
| **list_dropzone_files** / **read_dropzone_file** | Lists/reads files from the inbound dropzone. | No |
| **fetch_work_units** / **update_work_unit** | Reads/updates stigmergy board work units. | Yes → WorkUnit |
| **pin_ephemeral_note** | Writes short-lived note with TTL. | Yes → EphemeralPin |
| **list_resource_health** / **report_resource_failure** | Tracks cooldown/backoff for failing resources. | Yes → ResourceHealth |
| **read_research_snapshot** / **write_research_snapshot** | Local delta-tracking for repeating research. | Yes → ResearchSnapshot |
| **fetch_email_summaries** | Reads pre-summarized emails from CloudKit bridge. | No |

---

## 4. End-to-end example: "Plan trip logistics"

1. **iOS:** User creates objective "Plan San Diego trip logistics" → Rails persists it and decomposes into tasks like "Research hotel options", "Find flight prices", "Plan activities".
2. **Rails:** `TaskExecutorJob` POSTs webhooks to the Mac agent for each task.
3. **Mac:** `ObjectiveExecutionPool` picks up tasks. Workers call `multi_step_search` to compare hotels across sites, then `write_objective_snapshot` to persist findings.
4. **iOS:** User opens Objective Detail → sees whether action is required, the tasks currently being worked on, and a likely next check-in window. Opening Research shows the structured results layout plus the latest follow-up and its linked next-pass tasks.
5. **Log tab:** Shows the agent's research steps, tool calls, and outcomes.

---

## 5. Other Trigger Types

Beyond objectives, the Mac agent also processes:

| Trigger | Source | Priority |
|---------|--------|----------|
| **Webhook** | External POST to the agent's webhook port | High |
| **Chat message** | User sends a message in the iOS Chat tab | High |
| **Email file** | New `.eml` arrives in `~/.agentkvt/inbox/` | Normal |
| **Inbound file** | New file in `~/.agentkvt/inbound/` (dropzone) | Normal |
| **Clock tick** | Every N seconds (configurable, default 60s) | Low |
| **CloudKit sync** | Remote SwiftData change (legacy, non-backend mode) | High |

All triggers funnel through `AgentExecutionQueue`, which processes them one at a time (chat, email, clock) or dispatches to the `ObjectiveExecutionPool` (objective tasks).
