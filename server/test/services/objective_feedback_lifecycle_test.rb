require "test_helper"
require "securerandom"

class ObjectiveFeedbackLifecycleTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Lifecycle Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    @objective = @workspace.objectives.create!(goal: "Plan a beach weekend", status: "active")
  end

  test "marks feedback complete and stores a summary after all follow-up tasks finish" do
    feedback = @objective.objective_feedbacks.create!(
      content: "Compare the top two hotels by beach access.",
      feedback_kind: "compare_options",
      status: "queued"
    )
    task = @objective.tasks.create!(
      description: "Compare the two best hotels by beach access",
      status: "completed",
      result_summary: "Hotel del Coronado has direct beach access; Loews requires a shuttle",
      source_feedback: feedback
    )
    @objective.research_snapshots.create!(
      key: "beach_access",
      value: "Hotel del Coronado has direct beach access; Loews requires a shuttle",
      task: task,
      checked_at: Time.current
    )

    ObjectiveFeedbackLifecycle.new.refresh!(feedback)

    assert_equal "completed", feedback.reload.status
    assert feedback.completed_at.present?
    assert_includes feedback.completion_summary, "What changed"
    assert_includes feedback.completion_summary, "beach_access"
  end
end
