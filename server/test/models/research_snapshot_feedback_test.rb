require "test_helper"
require "securerandom"

class ResearchSnapshotFeedbackTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Test Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    @member = @workspace.family_members.create!(display_name: "Kevin", symbol: "K", source: "ios")
    @objective = @workspace.objectives.create!(goal: "Test objective", status: "active")
    @snapshot = @objective.research_snapshots.create!(key: "result", value: "Useful result", checked_at: Time.current)
  end

  test "accepts good and bad ratings" do
    good = ResearchSnapshotFeedback.new(
      workspace: @workspace,
      objective: @objective,
      research_snapshot: @snapshot,
      created_by_profile: @member,
      role: "user",
      rating: "good"
    )
    bad = ResearchSnapshotFeedback.new(
      workspace: @workspace,
      objective: @objective,
      research_snapshot: @snapshot,
      created_by_profile: @member,
      role: "user",
      rating: "bad"
    )

    assert good.valid?
    assert bad.valid?
  end

  test "rejects mismatched objective" do
    other = @workspace.objectives.create!(goal: "Other", status: "active")
    feedback = ResearchSnapshotFeedback.new(
      workspace: @workspace,
      objective: other,
      research_snapshot: @snapshot,
      created_by_profile: @member,
      role: "user",
      rating: "good"
    )

    assert_not feedback.valid?
    assert_includes feedback.errors[:objective], "must match the research snapshot objective"
  end

  test "enforces one feedback row per viewer and snapshot" do
    ResearchSnapshotFeedback.create!(
      workspace: @workspace,
      objective: @objective,
      research_snapshot: @snapshot,
      created_by_profile: @member,
      role: "user",
      rating: "good"
    )

    duplicate = ResearchSnapshotFeedback.new(
      workspace: @workspace,
      objective: @objective,
      research_snapshot: @snapshot,
      created_by_profile: @member,
      role: "user",
      rating: "bad"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:research_snapshot_id], "already has feedback from this viewer"
  end
end
