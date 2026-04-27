require "test_helper"
require "securerandom"

class ObjectiveFeedbackTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Feedback WS", slug: "ws-#{SecureRandom.hex(4)}", server_mode: "personal")
    @objective = @workspace.objectives.create!(goal: "Find best options", status: "active")
    @other_objective = @workspace.objectives.create!(goal: "Another objective", status: "active")
  end

  def valid_feedback(overrides = {})
    @objective.objective_feedbacks.new({
      role: "user",
      feedback_kind: "follow_up",
      status: "received",
      content: "Please dig deeper into pricing"
    }.merge(overrides))
  end

  # --- Validations ---

  test "valid with required fields" do
    fb = valid_feedback
    assert fb.valid?, fb.errors.full_messages.inspect
  end

  test "invalid without content" do
    fb = valid_feedback(content: nil)
    assert_not fb.valid?
    assert fb.errors[:content].any?
  end

  test "invalid role rejected" do
    fb = valid_feedback(role: "robot")
    assert_not fb.valid?
    assert fb.errors[:role].any?
  end

  test "valid roles accepted" do
    %w[user system].each do |role|
      fb = valid_feedback(role: role)
      assert fb.valid?, fb.errors.full_messages.inspect
    end
  end

  test "invalid feedback_kind rejected" do
    fb = valid_feedback(feedback_kind: "nonsense")
    assert_not fb.valid?
    assert fb.errors[:feedback_kind].any?
  end

  test "all valid feedback_kinds accepted" do
    ObjectiveFeedback::FEEDBACK_KINDS.each do |kind|
      fb = valid_feedback(feedback_kind: kind)
      assert fb.valid?, "Expected #{kind} to be valid: #{fb.errors.full_messages}"
    end
  end

  test "invalid status rejected" do
    fb = valid_feedback(status: "unknown_state")
    assert_not fb.valid?
    assert fb.errors[:status].any?
  end

  test "all valid statuses accepted" do
    ObjectiveFeedback::STATUSES.each do |s|
      fb = valid_feedback(status: s)
      assert fb.valid?, "Expected #{s} to be valid: #{fb.errors.full_messages}"
    end
  end

  # --- Cross-validation: task must belong to same objective ---

  test "task belonging to the same objective is accepted" do
    task = @objective.tasks.create!(description: "Search pricing", status: "pending")
    fb = valid_feedback(task: task)
    assert fb.valid?, fb.errors.full_messages.inspect
  end

  test "task belonging to a different objective is rejected" do
    other_task = @other_objective.tasks.create!(description: "Other work", status: "pending")
    fb = valid_feedback(task: other_task)
    assert_not fb.valid?
    assert_match(/must belong to the same objective/, fb.errors[:task].join)
  end

  # --- Cross-validation: research_snapshot must belong to same objective ---

  test "research_snapshot from same objective is accepted" do
    snapshot = @objective.research_snapshots.create!(key: "price", value: "Around $50")
    fb = valid_feedback(research_snapshot: snapshot)
    assert fb.valid?, fb.errors.full_messages.inspect
  end

  test "research_snapshot from different objective is rejected" do
    snapshot = @other_objective.research_snapshots.create!(key: "price", value: "Elsewhere")
    fb = valid_feedback(research_snapshot: snapshot)
    assert_not fb.valid?
    assert_match(/must belong to the same objective/, fb.errors[:research_snapshot].join)
  end

  # --- Cross-validation: snapshot task anchor must match task anchor ---

  test "snapshot with matching task_id accepted when both anchors provided" do
    task = @objective.tasks.create!(description: "Pricing research", status: "pending")
    snapshot = @objective.research_snapshots.create!(key: "price", value: "Around $50", task_id: task.id)
    fb = valid_feedback(task: task, research_snapshot: snapshot)
    assert fb.valid?, fb.errors.full_messages.inspect
  end

  test "snapshot with mismatched task_id rejected" do
    task1 = @objective.tasks.create!(description: "Task 1", status: "pending")
    task2 = @objective.tasks.create!(description: "Task 2", status: "pending")
    snapshot = @objective.research_snapshots.create!(key: "price", value: "Around $50", task_id: task1.id)
    fb = valid_feedback(task: task2, research_snapshot: snapshot)
    assert_not fb.valid?
    assert_match(/must match the selected task/, fb.errors[:research_snapshot].join)
  end

  test "snapshot with nil task_id is accepted alongside a task" do
    task = @objective.tasks.create!(description: "Any task", status: "pending")
    snapshot = @objective.research_snapshots.create!(key: "general", value: "General finding")
    fb = valid_feedback(task: task, research_snapshot: snapshot)
    assert fb.valid?, fb.errors.full_messages.inspect
  end

  # --- Scopes ---

  test "recent_first orders by created_at desc" do
    fb1 = @objective.objective_feedbacks.create!(role: "user", feedback_kind: "follow_up", status: "received", content: "First")
    fb2 = @objective.objective_feedbacks.create!(role: "user", feedback_kind: "follow_up", status: "received", content: "Second")
    ids = @objective.objective_feedbacks.recent_first.map(&:id)
    assert ids.index(fb2.id) < ids.index(fb1.id)
  end
end
