require "test_helper"
require "securerandom"

class SlackMessageTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "T", slug: "ws-#{SecureRandom.hex(4)}")
  end

  test "valid record" do
    msg = SlackMessage.create!(
      workspace: @workspace,
      slack_team_id: "T1",
      channel_id: "C1",
      message_ts: "1.0",
      slack_user_id: "U1",
      text: "hi",
      intake_kind: "user_typed",
      trust_tier: "low"
    )
    assert msg.persisted?
  end

  test "rejects invalid intake_kind" do
    msg = SlackMessage.new(
      workspace: @workspace,
      slack_team_id: "T1",
      channel_id: "C1",
      message_ts: "2.0",
      intake_kind: "bogus",
      trust_tier: "low"
    )
    assert_not msg.valid?
  end
end
