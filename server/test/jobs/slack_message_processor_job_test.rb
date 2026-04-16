require "test_helper"
require "securerandom"

class SlackMessageProcessorJobTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Slack Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    @objective = @workspace.objectives.create!(goal: "Track AI research signals", status: "active")
    @message = SlackMessage.create!(
      workspace: @workspace,
      slack_team_id: "T1",
      channel_id: "C1",
      message_ts: "1.0",
      slack_user_id: "U1",
      text: "Fresh headline from Slack",
      intake_kind: "user_typed",
      trust_tier: "low"
    )
  end

  test "append_research upserts the slack_signal snapshot" do
    @objective.research_snapshots.create!(
      key: "slack_signal",
      value: "Earlier signal",
      checked_at: 1.hour.ago
    )

    classifier_result = {
      "action" => "append_research",
      "objective_id" => @objective.id,
      "summary" => "Updated signal"
    }

    Slack::MessageClassifier.stub(:call, classifier_result) do
      assert_no_difference -> { @objective.research_snapshots.count } do
        SlackMessageProcessorJob.new.perform(@message.id)
      end
    end

    snapshot = @objective.research_snapshots.find_by!(key: "slack_signal")
    assert_equal "Updated signal", snapshot.value
    assert_equal "Earlier signal", snapshot.previous_value
    assert_equal "Changed from Earlier signal to Updated signal", snapshot.delta_note
  end
end
