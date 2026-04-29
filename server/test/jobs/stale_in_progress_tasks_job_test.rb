require "test_helper"
require "securerandom"

class StaleInProgressTasksJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = Workspace.create!(name: "Stale IP WS", slug: "ws-#{SecureRandom.hex(4)}", server_mode: "personal")
    @objective = @workspace.objectives.create!(goal: "Research best espresso machines", status: "active")
  end

  def create_task(overrides = {})
    @objective.tasks.create!({ description: "Find top espresso machines", status: "in_progress" }.merge(overrides))
  end

  test "resets stale in_progress tasks to pending and enqueues TaskExecutorJob" do
    task = create_task(claimed_at: 3.hours.ago, claimed_by_agent_id: "mac-agent-old")

    assert_enqueued_with(job: TaskExecutorJob) do
      StaleInProgressTasksJob.new.perform
    end

    task.reload
    assert_equal "pending", task.status
    assert_nil task.claimed_at
    assert_nil task.claimed_by_agent_id
  end

  test "ignores in_progress tasks claimed recently" do
    task = create_task(claimed_at: 30.minutes.ago, claimed_by_agent_id: "mac-agent-active")

    assert_no_enqueued_jobs do
      StaleInProgressTasksJob.new.perform
    end

    task.reload
    assert_equal "in_progress", task.status
  end

  test "ignores tasks with nil claimed_at" do
    task = create_task(claimed_at: nil)

    assert_no_enqueued_jobs do
      StaleInProgressTasksJob.new.perform
    end

    task.reload
    assert_equal "in_progress", task.status
  end

  test "resets multiple stale tasks independently" do
    task1 = create_task(description: "Task A", claimed_at: 4.hours.ago, claimed_by_agent_id: "mac-agent-1")
    task2 = create_task(description: "Task B", claimed_at: 6.hours.ago, claimed_by_agent_id: "mac-agent-2")
    fresh  = create_task(description: "Task C", claimed_at: 10.minutes.ago, claimed_by_agent_id: "mac-agent-3")

    assert_enqueued_jobs(2, only: TaskExecutorJob) do
      StaleInProgressTasksJob.new.perform
    end

    assert_equal "pending", task1.reload.status
    assert_equal "pending", task2.reload.status
    assert_equal "in_progress", fresh.reload.status
  end

  test "does nothing when no in_progress tasks exist" do
    @objective.tasks.create!(description: "Pending task", status: "pending")

    assert_no_enqueued_jobs do
      StaleInProgressTasksJob.new.perform
    end
  end
end
