require "test_helper"
require "securerandom"

class ObjectiveFeedbackCompletionSummaryBuilderTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Summary WS", slug: "ws-#{SecureRandom.hex(4)}", server_mode: "personal")
    @objective = @workspace.objectives.create!(goal: "Buy a laptop", status: "active")
    @feedback = @objective.objective_feedbacks.create!(
      role: "user",
      feedback_kind: "follow_up",
      status: "planned",
      content: "Please dig deeper into pricing"
    )
  end

  def builder
    ObjectiveFeedbackCompletionSummaryBuilder.new
  end

  # --- No completed tasks → nil ---

  test "returns nil when no completed follow-up tasks" do
    result = builder.call(@feedback)
    assert_nil result
  end

  test "returns nil when follow-up tasks exist but none are completed" do
    task = @objective.tasks.create!(description: "Search pricing", status: "in_progress")
    task.update_columns(source_feedback_id: @feedback.id)

    result = builder.call(@feedback)
    assert_nil result
  end

  # --- With completed tasks ---

  test "returns a string when completed follow-up tasks exist" do
    task = @objective.tasks.create!(description: "Check pricing", status: "completed")
    task.update_columns(source_feedback_id: @feedback.id)

    result = builder.call(@feedback)
    assert result.is_a?(String)
    assert result.present?
  end

  test "intro mentions the feedback kind and task count" do
    task = @objective.tasks.create!(description: "Find prices", status: "completed")
    task.update_columns(source_feedback_id: @feedback.id)

    result = builder.call(@feedback)
    assert_match(/follow.?up/i, result)
    assert_match(/1 follow-up task/, result)
  end

  test "intro uses plural when multiple tasks completed" do
    2.times do |i|
      task = @objective.tasks.create!(description: "Task #{i}", status: "completed")
      task.update_columns(source_feedback_id: @feedback.id)
    end

    result = builder.call(@feedback)
    assert_match(/2 follow-up tasks/, result)
  end

  # --- With recent snapshot updates ---

  test "includes delta_note from linked snapshots" do
    task = @objective.tasks.create!(description: "Verify price", status: "completed")
    task.update_columns(source_feedback_id: @feedback.id)
    snapshot = @objective.research_snapshots.create!(
      key: "laptop_price",
      value: "Now $1199",
      delta_note: "Changed from $1299 to $1199",
      task_id: task.id,
      checked_at: 5.minutes.ago
    )

    result = builder.call(@feedback)
    assert_match(/Changed from \$1299 to \$1199/, result)
  end

  test "falls back to task result_summary when no snapshot delta" do
    task = @objective.tasks.create!(
      description: "Check stock",
      status: "completed",
      result_summary: "In stock at Best Buy"
    )
    task.update_columns(source_feedback_id: @feedback.id)

    result = builder.call(@feedback)
    assert_match(/In stock at Best Buy/, result)
  end

  test "strips confidence options boilerplate from detail" do
    task = @objective.tasks.create!(description: "Verify price", status: "completed")
    task.update_columns(source_feedback_id: @feedback.id)
    @objective.research_snapshots.create!(
      key: "price_check",
      value: "In stock\nConfidence options: high, medium, low",
      task_id: task.id,
      checked_at: Time.current
    )

    result = builder.call(@feedback)
    refute_match(/Confidence options/i, result)
  end

  # --- humanize_key ---

  test "task_summary key is humanized to task description" do
    task = @objective.tasks.create!(description: "Research tradeoffs", status: "completed")
    task.update_columns(source_feedback_id: @feedback.id)
    @objective.research_snapshots.create!(
      key: "task_summary_#{task.id.to_s.first(4)}",
      value: "Tradeoffs documented",
      delta_note: "New analysis",
      task_id: task.id,
      checked_at: Time.current
    )

    result = builder.call(@feedback)
    assert_match(/Research tradeoffs/, result)
  end
end
