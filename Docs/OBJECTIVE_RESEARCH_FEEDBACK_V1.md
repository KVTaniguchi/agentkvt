# Objective Research Feedback Loop V1

## Summary

This V1 makes objectives feel continuous instead of one-shot.

After an objective produces research results, the user can give follow-up feedback from iPhone and ask AgentKVT to keep going. That feedback is stored, linked to the exact task or finding it refers to, and turned into 1-3 follow-up tasks. If the objective is already active, the new tasks are queued immediately. If the objective is still pending, the new tasks stay proposed until the user starts work.

This is the first objective-scoped collaboration loop after initial planning.

## Problem

Today, the system can:

- create an objective
- generate a plan
- run research tasks
- show results back on iPhone

But once results come back, the loop stops. Users cannot naturally say:

- "Go deeper on this result."
- "Compare these two options more carefully."
- "I do not trust this conclusion."
- "Turn this into a recommendation."

Without this loop, objectives feel like a batch job instead of a collaborative working session.

## V1 Goals

- Let the user continue research from the objective detail screen.
- Let feedback target the whole objective, a specific task, or a specific finding.
- Persist feedback as a first-class record.
- Convert each feedback submission into 1-3 linked follow-up tasks.
- Auto-queue follow-up tasks when the objective is active.
- Show the feedback history and resulting work in the same objective timeline.

## Non-Goals

- Full chat threads between the user and an individual task worker
- Editing or deleting feedback after submission
- Inline approve/reject controls on each individual follow-up task
- Agent-authored replies inside the feedback thread

## Primary User Story

1. User opens an objective that already has completed tasks or research findings.
2. User sees a `Continue Research` composer on the objective detail screen or the research results screen.
3. User chooses an intent like `Compare options`.
4. User optionally anchors the feedback to a finding or task.
5. User writes: `Compare these two hotels by resort fee, beach access, and kid-friendliness.`
6. AgentKVT creates follow-up tasks linked to that feedback.
7. If the objective is active, the tasks begin running.
8. The user sees the new feedback entry and resulting follow-up tasks in the objective detail flow.

## Exact UI

### Screen placement

V1 lives in:

- [ObjectiveDetailView.swift](../AgentKVTiOS/Views/ObjectiveDetailView.swift)
- [GenerativeResultsView.swift](../AgentKVTiOS/Views/GenerativeResultsView.swift)

On objective detail, it appears below the `Research` section and above `Recent Agent Logs`.

On the research results screen, it appears as a bottom action area anchored above the safe area.

### Visibility rules

Show the `Continue Research` composer when:

- the objective has at least one completed task, or
- the objective has at least one research snapshot, or
- the objective already has at least one feedback entry

And only when objective status is:

- `pending`
- `active`

Hide it for:

- `completed`
- `archived`

### Continue Research section

Header:

- `Continue Research`

Controls:

1. `Intent` menu
   - `Go deeper` -> `follow_up`
   - `Compare options` -> `compare_options`
   - `Challenge result` -> `challenge_result`
   - `Clarify gaps` -> `clarify_gaps`
   - `Recommend next move` -> `final_recommendation`

2. `Focus` menu
   - always includes `Entire objective`
   - then up to 6 recent findings
     - label format: `Finding: <snapshot.key>`
   - then up to 8 recent tasks
     - label format: `Task: <task.description>`
   - only shown when there is more than one possible target

3. Multiline text field
   - placeholder: `Tell AgentKVT what to research next...`
   - 3-6 visible lines

4. Primary CTA
   - label: `Create follow-up tasks`
   - icon: branch/continuation affordance
   - disabled when:
     - text is empty
     - submission is already in progress
     - another objective action is in progress
     - delete flow is in progress

Footer copy:

- `Submitting feedback creates 1-3 new follow-up tasks. Active objectives queue them automatically so the agent can keep going.`

### Research results screen entry point

The research results screen adds a lighter-weight entry point for the same workflow.

Bottom action area contents:

- section label: `Guide the next pass`
- quick intent buttons:
  - `Go deeper`
  - `Compare options`
  - `Challenge result`
- primary CTA:
  - `Continue Research`

Behavior:

- tapping a quick intent opens the same composer sheet with that intent preselected
- tapping `Continue Research` opens the composer with `Go deeper` preselected
- composer is presented as a sheet with medium and large detents
- on success, the screen shows a confirmation message:
  - active objective: `Follow-up tasks were queued for the agent.`
  - pending objective: `Follow-up tasks were added to this objective for later review.`

### Submission behavior

On submit:

- button shows loading state
- composer posts feedback to backend
- detail refreshes
- input clears on success
- intent resets to `Go deeper`
- focus resets to `Entire objective`

If objective is `active`:

- view performs a short refresh burst so newly queued work appears quickly

### Feedback Loop section

If at least one feedback entry exists, show a `Feedback Loop` section.

Each row shows:

- intent chip
- feedback status
  - `Received`
  - `Planned`
  - `Queued`
  - `Failed`
- relative timestamp
- target label
  - `Entire objective`
  - `Finding: <snapshot.key>`
  - `Task: <task.description>`
- feedback content
- count of follow-up tasks created from that feedback

### Task list affordance

Tasks created from feedback should display as follow-up work by checking `source_feedback_id != nil`.

## API Endpoints

### 1. Objective detail

`GET /v1/objectives/:id`

Purpose:

- return the objective detail screen payload
- now includes feedback history
- now returns task-to-feedback linkage

New response fields:

- `objective_feedbacks`: array
- `tasks[].source_feedback_id`

Response shape additions:

```json
{
  "tasks": [
    {
      "id": "task-id",
      "objective_id": "objective-id",
      "source_feedback_id": "feedback-id",
      "description": "Compare resort fees",
      "status": "pending",
      "result_summary": null
    }
  ],
  "objective_feedbacks": [
    {
      "id": "feedback-id",
      "objective_id": "objective-id",
      "task_id": "optional-task-id",
      "research_snapshot_id": "optional-snapshot-id",
      "role": "user",
      "feedback_kind": "compare_options",
      "status": "queued",
      "content": "Go deeper on resort fees and beach access.",
      "created_at": "2026-04-10T10:00:00Z",
      "updated_at": "2026-04-10T10:01:00Z"
    }
  ]
}
```

### 2. Submit follow-up feedback

`POST /v1/objectives/:id/feedback`

Purpose:

- create a new objective feedback record
- generate follow-up tasks from that feedback
- auto-queue them if the objective is active

Request body:

```json
{
  "objective_feedback": {
    "content": "Compare these two options by resort fee and beach access.",
    "feedback_kind": "compare_options",
    "task_id": "optional-task-id",
    "research_snapshot_id": "optional-snapshot-id"
  }
}
```

Rules:

- `content` is required
- `feedback_kind` defaults to `follow_up` if omitted server-side only if model default is used, but clients should always send it
- `task_id` is optional
- `research_snapshot_id` is optional
- if both anchors are present, the snapshot must belong to the same task
- anchors must belong to the same objective
- objective must be `pending` or `active`

Success response:

```json
{
  "objective": { "...": "updated objective payload" },
  "objective_feedback": {
    "id": "feedback-id",
    "objective_id": "objective-id",
    "task_id": "optional-task-id",
    "research_snapshot_id": "optional-snapshot-id",
    "role": "user",
    "feedback_kind": "compare_options",
    "status": "queued",
    "content": "Compare these two options by resort fee and beach access.",
    "created_at": "2026-04-10T10:00:00Z",
    "updated_at": "2026-04-10T10:00:00Z"
  }
}
```

Status codes:

- `201 Created` on success
- `422 Unprocessable Entity` when:
  - objective status does not allow feedback
  - task/snapshot anchor belongs to another objective
  - task/snapshot anchor pair is inconsistent

## Server Behavior

### Happy path

1. Find objective by workspace and id
2. Reject unless objective status is `pending` or `active`
3. Create `ObjectiveFeedback` with:
   - `role = "user"`
   - `status = "received"`
4. Run follow-up planner
5. Persist 1-3 tasks linked with `source_feedback_id`
6. Update feedback status:
   - `queued` if objective is `active`
   - `planned` if objective is `pending`
7. If objective is `active`, call `ObjectiveKickoff` so pending follow-up tasks dispatch immediately
8. Return updated objective + created feedback

### Planner behavior

Planner input should include:

- objective goal
- structured objective summary
- user feedback content
- referenced task, if present
- referenced finding, if present
- recent completed tasks
- recent research snapshots

Planner output:

- JSON array of 1-3 task objects
- each task object has `description`

Fallback behavior:

- if LLM output is invalid or the model call fails, generate heuristic follow-up task descriptions

### Task status rules

- Objective `active` -> created follow-up tasks start as `pending`
- Objective `pending` -> created follow-up tasks start as `proposed`

## Data Model

### New table: `objective_feedbacks`

Columns:

- `id`
- `objective_id`
- `task_id` nullable
- `research_snapshot_id` nullable
- `role`
- `feedback_kind`
- `status`
- `content`
- `created_at`
- `updated_at`

Enums:

- `role`
  - `user`
  - `system`
- `feedback_kind`
  - `follow_up`
  - `compare_options`
  - `challenge_result`
  - `clarify_gaps`
  - `final_recommendation`
- `status`
  - `received`
  - `planned`
  - `queued`
  - `failed`

Associations:

- `Objective has_many :objective_feedbacks`
- `ObjectiveFeedback belongs_to :objective`
- `ObjectiveFeedback belongs_to :task, optional: true`
- `ObjectiveFeedback belongs_to :research_snapshot, optional: true`
- `ObjectiveFeedback has_many :follow_up_tasks, foreign_key: :source_feedback_id`

### Existing table change: `tasks`

New column:

- `source_feedback_id` nullable

Purpose:

- link any generated follow-up task back to the feedback that created it

## V1 Constraints

- V1 feedback entry points are objective detail and research results only
- V1 does not support user comments on individual task rows inline
- V1 does not support agent-written conversational replies
- V1 uses one-shot follow-up planning, not a long-lived feedback thread runner
- V1 does not expose partial approval per follow-up task

## Success Criteria

- User can submit follow-up research feedback from iPhone without leaving the objective flow
- User can start follow-up research directly from the research results screen
- Feedback is persisted and visible in objective history
- Each feedback entry creates 1-3 linked tasks
- Active objectives queue follow-up tasks automatically
- Pending objectives keep follow-up tasks reviewable
- User can tell which tasks came from which feedback

## Change Amount

The current scoped V1 implementation footprint is:

- 19 scoped files
- 1 new API endpoint
- 2 existing response payloads extended
- 1 new persisted table
- 1 new foreign key on `tasks`
- about 1,795 added lines
- 3 removed lines

Scoped breakdown:

- iOS product code: 4 files
  - [IOSBackendAPIClient.swift](../AgentKVTiOS/Services/IOSBackendAPIClient.swift)
  - [ObjectivesStore.swift](../AgentKVTiOS/Stores/ObjectivesStore.swift)
  - [ObjectiveDetailView.swift](../AgentKVTiOS/Views/ObjectiveDetailView.swift)
  - [GenerativeResultsView.swift](../AgentKVTiOS/Views/GenerativeResultsView.swift)
- iOS tests: 3 files
  - [IOSBackendAPIClientTests.swift](../AgentKVTiOS/AgentKVTiOSTests/IOSBackendAPIClientTests.swift)
  - [ObjectivesStoreTests.swift](../AgentKVTiOS/AgentKVTiOSTests/ObjectivesStoreTests.swift)
  - [RemoteModelsDecodingTests.swift](../AgentKVTiOS/AgentKVTiOSTests/RemoteModelsDecodingTests.swift)
- server application code: 9 files
  - controller
  - serialization concern
  - model updates
  - new feedback model
  - new planner service
  - routes
  - migration
  - schema
- server tests: 3 files
  - integration coverage
  - new planner service test
  - related objective coverage

Note:

- these numbers are scoped to the feedback-loop V1 work only
- they exclude unrelated worktree changes already in progress elsewhere in the repo

## Rollout Notes

1. Run migration to create `objective_feedbacks` and `tasks.source_feedback_id`
2. Deploy server first
3. Verify `GET /v1/objectives/:id` still works for older clients
4. Ship iOS build with the new composer
5. Verify one active-objective flow and one pending-objective flow end to end

## Future V2

Likely next improvements after V1:

- anchor follow-up feedback directly to tapped cards inside the generative presentation
- let users regenerate only follow-up tasks from one feedback entry
- add agent-authored status text or reply summaries
- support feedback editing or cancellation
- allow approve/reject at the follow-up task batch level
