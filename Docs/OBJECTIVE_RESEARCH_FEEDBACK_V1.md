# Objective Research Feedback Loop V1

This document now serves as the current-design reference for the shipped V1 follow-up loop in:

- [ObjectiveDetailView.swift](../AgentKVTiOS/Views/ObjectiveDetailView.swift)
- [GenerativeResultsView.swift](../AgentKVTiOS/Views/GenerativeResultsView.swift)
- [IOSBackendAPIClient.swift](../AgentKVTiOS/Services/IOSBackendAPIClient.swift)

## Summary

AgentKVT now treats research as an ongoing loop instead of a one-shot batch.

After research results appear, the user can submit follow-up feedback from iPhone, anchor it to the whole objective, a task, or a specific finding, and create a reviewable next pass. The Research screen is the primary home for this loop. It shows the latest follow-up, the agent activity tied to that follow-up, and the historical follow-up loop in one place. Objective Detail is the secondary management surface: it tells the user whether they need to act now, can come back later, or should review a queued next pass before the Mac continues.

## Current UX Principles

- Use one narrative: `user feedback -> next-pass plan -> queued/running work -> completed outcome`.
- Keep the Research screen as the canonical answer to "what happened to my feedback?"
- Make Objective Detail answer two questions immediately:
  - What should I do next?
  - What is the Mac doing right now?
- Never show competing primary actions when a follow-up batch is waiting for review.
- When work is already active, tell the user that no action is needed and show concrete live progress instead of raw telemetry only.

## Goals

- Let the user continue research from either Objective Detail or the Research screen.
- Persist follow-up feedback as a first-class record anchored to the objective, task, or finding it refers to.
- Convert each feedback submission into a linked next-pass task batch.
- Keep review, approval, regeneration, and completion visible in the same history model.
- Give the user a clear top-of-screen state in Objective Detail for review-required, queued, and active-work moments.

## Non-Goals

- Full conversational threads between the user and one task worker
- Per-task approve/reject controls inside a follow-up batch
- Deleting follow-up feedback after submission
- Exact completion ETAs or guaranteed countdown timers
- Agent-authored replies inside the follow-up loop

## Primary User Stories

### 1. Continue research from the Research screen

1. User opens a research result.
2. User taps `Continue Research` or a quick intent such as `Challenge result`.
3. The composer shows the intended target and a compact context summary.
4. User submits feedback.
5. The sheet first shows `Sending your feedback`, then `Feedback received`.
6. The system creates a next pass and returns a follow-up card with a status such as `Ready for review`, `Queued for agent`, or `Saved for later`.
7. After dismissal, the Research screen pins the entry as `Latest Follow-up` and keeps it visible in the `Follow-up Loop`.

### 2. Review a follow-up batch before more work continues

1. User opens Objective Detail.
2. The top `Activity` section says `Next step: Review follow-up`.
3. The review-required follow-up card is promoted directly under the activity summary.
4. The user can `Approve`, `Regenerate`, or `Edit`.
5. If approved and the objective is active, the Mac queues/runs the new work.

### 3. Monitor active work without guessing what to press

1. User opens Objective Detail while tasks are already running.
2. The top `Activity` section says `No action needed right now`.
3. The screen shows:
   - `Likely next check-in`
   - `Working On Now`
   - `Recently Finished`
4. Recovery controls remain available, but `Run now` does not compete with active work.

## Current UI

### Research Screen

The Research screen is the primary home for follow-up feedback after submission.

Current structure:

- server-rendered research layout
- `Latest Follow-up`
- `Agent Activity`
- `Follow-up Loop`
- `Continue from a finding`
- bottom safe-area action area: `Guide the next pass`

The bottom action area contains:

- quick intent buttons:
  - `Go deeper`
  - `Compare options`
  - `Challenge result`
- primary CTA:
  - `Continue Research`

Behavior:

- quick intents open the same composer sheet with that intent preselected
- `Continue Research` opens the composer with `Go deeper` preselected
- when a follow-up submission times out, the Research screen keeps polling and shows a visible `Still working` state instead of silently dropping the request
- the agent activity copy references the latest follow-up whenever possible

### Follow-up Composer Sheet

The Research screen uses a dedicated sheet. Objective Detail still uses an inline `Continue Research` section for new submissions when no review-required follow-up is currently promoted.

Current composer structure:

- title:
  - `Continue Research`
  - `Edit Follow-up Plan` when editing a reviewable batch
- `Context` section with:
  - intent chip
  - target label
  - target preview
- `Next Pass` section with:
  - `Intent` menu
  - `Focus` menu
  - multiline text field
  - primary CTA:
    - `Create Next Pass`
    - `Update Follow-up` while editing

Footer copy:

- active objectives: approved follow-up work can queue automatically
- pending objectives: larger next passes stay saved for later review

Submission states:

- `editing`
- `submitting`
- `received_building_plan`
- `success`
- `timedOut`

Important UX behavior:

- the sheet is non-dismissible during `submitting` and `received_building_plan`
- the sheet stays visible long enough to acknowledge receipt
- success shows the resulting follow-up card and a `Back to Research` / `Done` button
- timeout shows the pending follow-up card and explains that the Research screen will keep refreshing

### Objective Detail

Objective Detail is the secondary management surface.

Current top-of-screen states:

- `Plan ready for review`
- `Approved plan ready`
- `Next step: Review follow-up`
- `No action needed right now`
- `Tasks are queued`
- `Research available`

When a follow-up batch is waiting for review:

- the top card says `Next step: Review follow-up`
- the follow-up card is promoted directly under Activity
- the promoted card shows `Approve`, `Regenerate`, and `Edit`
- the inline `Continue Research` composer is hidden to avoid competing actions

When work is active:

- the top card says `No action needed right now`
- the card includes `Likely next check-in`
- `Working On Now` shows up to three active tasks
- `Recently Finished` shows the latest completed tasks
- each live row uses Mac log metadata to show:
  - task title
  - worker/phase
  - latest tool or supervisor update
  - relative timestamp
- if more queued work still exists, the only forward action is `Dispatch queued tasks now`
- otherwise the remaining lower controls are recovery-only

### Shared Follow-up Card

The same follow-up card model is used across Research and Objective Detail.

Each card shows:

- intent chip
- normalized status label
- relative timestamp
- target label
- target preview when available
- feedback content
- optional status message
- linked task disclosure
- completion summary when present

When the status is `review_required`, the card can show:

- `Approve` or `Approve & queue`
- `Regenerate`
- `Edit`

## Status Model

### Backend statuses

- `received`
- `review_required`
- `planned`
- `queued`
- `completed`
- `failed`

`received` is generally short-lived and quickly transitions once the planner/lifecycle pass finishes.

### Client-only presentation states

- `submitting`
- `received_building_plan`
- `timed_out_but_refreshing`

### User-facing status labels

- `review_required` -> `Ready for review`
- `queued` -> `Queued for agent`
- `planned` -> `Saved for later`
- `completed` -> `Completed`
- `failed` -> `Needs attention`
- `submitting` -> `Sending feedback`
- `received_building_plan` -> `Creating next pass`
- `timed_out_but_refreshing` -> `Still working`

## API Surface

### 1. Objective detail

`GET /v1/objectives/:id`

This is the canonical payload for Objective Detail and the Research activity overlay.

It returns:

- `objective`
- `tasks`
- `research_snapshots`
- `objective_feedbacks`
- `agent_logs`
- `online_agent_registrations_count`

Important payload additions for the follow-up loop:

- `tasks[].source_feedback_id`
- `objective_feedbacks[].completion_summary`
- `objective_feedbacks[].completed_at`

Example shape:

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
      "status": "review_required",
      "content": "Go deeper on resort fees and beach access.",
      "completion_summary": null,
      "completed_at": null,
      "created_at": "2026-04-10T10:00:00Z",
      "updated_at": "2026-04-10T10:01:00Z"
    }
  ]
}
```

### 2. Create follow-up feedback

`POST /v1/objectives/:id/feedback`

Creates a new feedback entry, generates the next-pass task batch, refreshes lifecycle state, and kicks off work immediately when the objective is active and the batch is queueable.

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

Success response:

```json
{
  "objective": { "...": "updated objective payload" },
  "objective_feedback": {
    "id": "feedback-id",
    "status": "queued",
    "content": "Compare these two options by resort fee and beach access."
  },
  "follow_up_tasks": [
    {
      "id": "task-id",
      "source_feedback_id": "feedback-id",
      "description": "Compare resort fees"
    }
  ]
}
```

### 3. Update a reviewable follow-up

`PATCH /v1/objectives/:objective_id/objective_feedbacks/:id`

Used by the `Edit` action on a reviewable next pass. The server updates the feedback record, deletes still-proposed linked tasks, rebuilds the next pass, refreshes lifecycle state, and re-kicks work if the result is queueable.

### 4. Approve a reviewable follow-up batch

`POST /v1/objectives/:objective_id/objective_feedbacks/:id/approve_plan`

Moves the linked proposed tasks to `pending`, refreshes lifecycle state, and dispatches them immediately if the objective is active.

### 5. Regenerate a reviewable follow-up batch

`POST /v1/objectives/:objective_id/objective_feedbacks/:id/regenerate_plan`

Deletes the existing proposed follow-up tasks, rebuilds the batch, refreshes lifecycle state, and dispatches if the objective is active and the new batch is queueable.

## Server Behavior

### Create flow

1. Find objective by workspace and id.
2. Reject unless objective status is `pending` or `active`.
3. Create `ObjectiveFeedback` with:
   - `role = "user"`
   - `status = "received"`
4. Run `ObjectiveFeedbackPlanner`.
5. Persist 1-3 linked tasks with `source_feedback_id`.
6. Run `ObjectiveFeedbackLifecycle.refresh!` to derive the real feedback state.
7. If the refreshed state is `queued`, call `ObjectiveKickoff`.
8. Return the updated objective, feedback, and linked tasks.

### Lifecycle rules

`ObjectiveFeedbackLifecycle` maps linked task state to feedback state:

- any linked `proposed` task -> `review_required`
- active/pending linked work on an active objective -> `queued`
- active/pending linked work on a pending objective -> `planned`
- all linked tasks completed -> `completed`
- any linked task failed -> `failed`

On completion, the lifecycle also stores:

- `completed_at`
- `completion_summary`

### Planner inputs

The planner should consider:

- objective goal
- structured planner summary / brief
- user feedback content
- selected task anchor, if present
- selected finding anchor, if present
- recent completed tasks
- recent research snapshots

Fallback behavior:

- if LLM output is invalid or unavailable, generate heuristic follow-up task descriptions

## Data Model

### `objective_feedbacks`

Columns:

- `id`
- `objective_id`
- `task_id` nullable
- `research_snapshot_id` nullable
- `role`
- `feedback_kind`
- `status`
- `content`
- `completion_summary` nullable
- `completed_at` nullable
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
  - `review_required`
  - `planned`
  - `queued`
  - `completed`
  - `failed`

Associations:

- `Objective has_many :objective_feedbacks`
- `ObjectiveFeedback belongs_to :objective`
- `ObjectiveFeedback belongs_to :task, optional: true`
- `ObjectiveFeedback belongs_to :research_snapshot, optional: true`
- `ObjectiveFeedback has_many :follow_up_tasks, foreign_key: :source_feedback_id`

### `tasks`

Current follow-up linkage:

- `source_feedback_id` nullable

Purpose:

- link any generated follow-up task back to the feedback that created it
- support Research `Latest Follow-up` / `Follow-up Loop`
- support Objective Detail live task monitoring for the latest follow-up

## Success Criteria

- User can submit follow-up research feedback from iPhone without leaving the objective flow.
- The Research screen shows receipt, success, or timeout clearly instead of silently dismissing.
- The Research screen pins the latest follow-up and keeps a readable follow-up history.
- Objective Detail tells the user whether they should review, wait, or recover from a stalled run.
- Active work shows concrete `Working On Now` and `Recently Finished` rows instead of only metric chips.
- The app can suggest a reasonable `Likely next check-in` when enough task timing data exists.
- Reviewable follow-up batches can be approved, regenerated, or edited at the batch level.
- Active objectives queue approved follow-up tasks automatically.
- Pending objectives keep follow-up work reviewable/saved for later.
- Users can tell which tasks came from which feedback entry.

## Constraints

- Entry points remain Objective Detail and Research only.
- This is still a batch-level next-pass model, not a long-lived follow-up conversation runner.
- Partial approval inside one follow-up batch is not supported.
- Objective Detail is a secondary management surface; Research remains the primary follow-up home.

## Future V2

Likely next improvements:

- local/push notifications when review is needed or the run completes
- stronger confidence scoring for `Likely next check-in`
- richer agent-authored completion summaries and rationale
- follow-up analytics across multiple batches
- finer-grained controls for large next-pass batches
