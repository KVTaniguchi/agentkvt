require "test_helper"
require "securerandom"

class ObjectiveKickoffTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    @workspace = Workspace.create!(name: "Kickoff WS", slug: "ws-#{SecureRandom.hex(4)}", server_mode: "personal")
    @objective = @workspace.objectives.create!(goal: "Plan a trip", status: "pending")
  end

  # --- Status promotion ---

  test "activates pending objective" do
    ObjectiveKickoff.new.call(@objective)
    assert_equal "active", @objective.reload.status
  end

  test "leaves already-active objective unchanged" do
    @objective.update!(status: "active")
    ObjectiveKickoff.new.call(@objective)
    assert_equal "active", @objective.reload.status
  end

  # --- No tasks: enqueues ObjectivePlannerJob ---

  test "enqueues ObjectivePlannerJob when objective has no tasks" do
    assert_enqueued_with(job: ObjectivePlannerJob) do
      ObjectiveKickoff.new.call(@objective)
    end
  end

  test "does not enqueue TaskExecutorJob when objective has no tasks" do
    assert_no_enqueued_jobs(only: TaskExecutorJob) do
      ObjectiveKickoff.new.call(@objective)
    end
  end

  # --- Has pending tasks: enqueues TaskExecutorJob ---

  test "enqueues TaskExecutorJob for each pending task when tasks exist" do
    @objective.tasks.create!(description: "Search flights", status: "pending")
    @objective.tasks.create!(description: "Search hotels", status: "pending")

    assert_enqueued_with(job: TaskExecutorJob) do
      ObjectiveKickoff.new.call(@objective)
    end
  end

  test "does not enqueue ObjectivePlannerJob when tasks already exist" do
    @objective.tasks.create!(description: "Existing task", status: "pending")
    assert_no_enqueued_jobs(only: ObjectivePlannerJob) do
      ObjectiveKickoff.new.call(@objective)
    end
  end

  # --- Has failed tasks: resets to pending and enqueues ---

  test "resets failed tasks to pending before enqueuing" do
    task = @objective.tasks.create!(
      description: "Failed research",
      status: "failed",
      result_summary: "Error occurred"
    )

    ObjectiveKickoff.new.call(@objective)

    task.reload
    assert_equal "pending", task.status
    assert_nil task.result_summary
  end

  test "does not re-enqueue already in_progress tasks" do
    @objective.tasks.create!(description: "In flight", status: "in_progress")

    assert_no_enqueued_jobs(only: TaskExecutorJob) do
      ObjectiveKickoff.new.call(@objective)
    end
  end

  # --- Feedback refresh (tested via observable status transitions) ---

  test "transitions feedback to queued when follow-up task is pending and objective becomes active" do
    task = @objective.tasks.create!(description: "Follow-up search", status: "pending")
    feedback = @objective.objective_feedbacks.create!(
      role: "user",
      feedback_kind: "follow_up",
      status: "planned",
      content: "Please search more"
    )
    task.update_columns(source_feedback_id: feedback.id)

    ObjectiveKickoff.new.call(@objective)

    # ObjectiveFeedbackLifecycle.refresh! sees a pending task on an active objective → queued
    assert_equal "queued", feedback.reload.status
  end

  test "leaves feedback status unchanged when it has no follow-up tasks" do
    feedback = @objective.objective_feedbacks.create!(
      role: "user",
      feedback_kind: "follow_up",
      status: "received",
      content: "Some feedback with no tasks"
    )

    ObjectiveKickoff.new.call(@objective)

    # kickoff skips feedbacks with no follow_up_tasks → status unchanged
    assert_equal "received", feedback.reload.status
  end
end
