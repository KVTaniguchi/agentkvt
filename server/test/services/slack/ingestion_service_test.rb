require "test_helper"
require "securerandom"

class Slack::IngestionServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    @workspace = Workspace.create!(name: "Slack WS", slug: "ws-#{SecureRandom.hex(4)}", server_mode: "personal")
    @team_id = "T#{SecureRandom.hex(4)}"
    SlackWorkspaceLink.create!(workspace: @workspace, slack_team_id: @team_id)
  end

  def event_payload(event_overrides = {}, overrides = {})
    {
      "type" => "event_callback",
      "team_id" => @team_id,
      "event_id" => "Ev#{SecureRandom.hex(4)}",
      "event_time" => Time.now.to_i,
      "api_app_id" => "A123",
      "event" => {
        "type" => "message",
        "channel" => "C001",
        "user" => "U001",
        "text" => "Hello world",
        "ts" => "#{Time.now.to_f}"
      }.merge(event_overrides)
    }.merge(overrides)
  end

  # --- Ignored payloads ---

  test "returns :ignored for non-hash payload" do
    result = Slack::IngestionService.call("not a hash")
    assert_equal :ignored, result
  end

  test "returns :ignored when type is not event_callback" do
    result = Slack::IngestionService.call(event_payload.merge("type" => "url_verification"))
    assert_equal :ignored, result
  end

  test "returns :unknown_team when team_id is not registered" do
    payload = event_payload({}, "team_id" => "T_unknown")
    result = Slack::IngestionService.call(payload)
    assert_equal :unknown_team, result
  end

  # --- skip_event? ---

  test "returns :ignored for channel_join subtype" do
    result = Slack::IngestionService.call(event_payload("subtype" => "channel_join"))
    assert_equal :ignored, result
  end

  test "returns :ignored for channel_leave subtype" do
    result = Slack::IngestionService.call(event_payload("subtype" => "channel_leave"))
    assert_equal :ignored, result
  end

  test "returns :ignored when text is blank" do
    result = Slack::IngestionService.call(event_payload("text" => ""))
    assert_equal :ignored, result
  end

  test "returns :ignored for bot messages in non-feed channels" do
    result = Slack::IngestionService.call(event_payload("bot_id" => "B001", "user" => nil))
    assert_equal :ignored, result
  end

  test "returns :ignored for human messages without user field" do
    result = Slack::IngestionService.call(event_payload("user" => nil, "bot_id" => nil))
    assert_equal :ignored, result
  end

  # --- persist_message! ---

  test "persists a valid human message and returns :persisted" do
    assert_difference -> { SlackMessage.count }, 1 do
      result = Slack::IngestionService.call(event_payload)
      assert_equal :persisted, result
    end
  end

  test "persisted message has correct attributes" do
    payload = event_payload
    Slack::IngestionService.call(payload)

    msg = SlackMessage.last
    assert_equal @workspace, msg.workspace
    assert_equal @team_id, msg.slack_team_id
    assert_equal "C001", msg.channel_id
    assert_equal "U001", msg.slack_user_id
    assert_equal "Hello world", msg.text
    assert_equal "user_typed", msg.intake_kind
    assert_equal "low", msg.trust_tier
  end

  test "idempotent: same ts+channel upserts instead of duplicating" do
    payload = event_payload
    Slack::IngestionService.call(payload)
    assert_no_difference -> { SlackMessage.count } do
      Slack::IngestionService.call(payload)
    end
  end

  test "enqueues SlackMessageProcessorJob after persist" do
    assert_enqueued_with(job: SlackMessageProcessorJob) do
      Slack::IngestionService.call(event_payload)
    end
  end

  # --- feed channel bot messages ---

  test "persists bot message from feed channel with feed_bot intake_kind" do
    feed_channel = "C_FEED"
    with_env("SLACK_FEED_CHANNEL_IDS", feed_channel) do
      bot_payload = event_payload(
        "channel" => feed_channel,
        "bot_id" => "B001",
        "user" => nil,
        "subtype" => "bot_message"
      )
      result = Slack::IngestionService.call(bot_payload)
      assert_equal :persisted, result

      msg = SlackMessage.last
      assert_equal "feed_bot", msg.intake_kind
      assert_equal "medium", msg.trust_tier
    end
  end

  test "ignores bot message from non-feed channel even with SLACK_FEED_CHANNEL_IDS set" do
    with_env("SLACK_FEED_CHANNEL_IDS", "C_FEED") do
      bot_payload = event_payload(
        "channel" => "C_OTHER",
        "bot_id" => "B001",
        "user" => nil
      )
      result = Slack::IngestionService.call(bot_payload)
      assert_equal :ignored, result
    end
  end

  # --- missing channel/ts ---

  test "returns :ignored when channel is missing" do
    result = Slack::IngestionService.call(event_payload("channel" => nil))
    assert_equal :ignored, result
  end

  test "returns :ignored when message_ts is missing" do
    result = Slack::IngestionService.call(event_payload("ts" => nil))
    assert_equal :ignored, result
  end

  private

  def with_env(key, value, &block)
    original = ENV[key]
    ENV[key] = value
    block.call
  ensure
    ENV[key] = original
  end
end
