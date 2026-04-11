require "test_helper"
require "openssl"
require "securerandom"

class V1SlackEventsTest < ActionDispatch::IntegrationTest
  SLACK_SECRET = "test_slack_signing_secret"

  setup do
    @old_slack_secret = ENV["SLACK_SIGNING_SECRET"]
    ENV["SLACK_SIGNING_SECRET"] = SLACK_SECRET
    @workspace = Workspace.create!(name: "Slack WS", slug: "workspace-#{SecureRandom.hex(4)}")
  end

  teardown do
    if @old_slack_secret
      ENV["SLACK_SIGNING_SECRET"] = @old_slack_secret
    else
      ENV.delete("SLACK_SIGNING_SECRET")
    end
  end

  def slack_signature(body, ts)
    sig_basestring = "v0:#{ts}:#{body}"
    "v0=#{OpenSSL::HMAC.hexdigest('SHA256', SLACK_SECRET, sig_basestring)}"
  end

  def post_slack_event(body, ts: Time.now.to_i.to_s)
    post "/v1/slack/events",
         params: body,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "X-Slack-Request-Timestamp" => ts,
           "X-Slack-Signature" => slack_signature(body, ts)
         }
  end

  test "url_verification returns challenge JSON" do
    body = { type: "url_verification", challenge: "abc123xyz" }.to_json
    post_slack_event(body)
    assert_response :success
    assert_equal "abc123xyz", JSON.parse(response.body)["challenge"]
  end

  test "malformed json body returns 400" do
    body = "not-json"
    ts = Time.now.to_i.to_s
    post "/v1/slack/events",
         params: body,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "X-Slack-Request-Timestamp" => ts,
           "X-Slack-Signature" => slack_signature(body, ts)
         }
    assert_response :bad_request
  end

  test "rejects invalid signature with 401" do
    body = { type: "url_verification", challenge: "x" }.to_json
    ts = Time.now.to_i.to_s
    post "/v1/slack/events",
         params: body,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "X-Slack-Request-Timestamp" => ts,
           "X-Slack-Signature" => "v0=invalid"
         }
    assert_response :unauthorized
  end

  test "returns 500 when SLACK_SIGNING_SECRET is not configured" do
    body = { type: "url_verification", challenge: "x" }.to_json
    ts = Time.now.to_i.to_s
    sig = slack_signature(body, ts)
    old = ENV.delete("SLACK_SIGNING_SECRET")
    begin
      post "/v1/slack/events",
           params: body,
           headers: {
             "CONTENT_TYPE" => "application/json",
             "X-Slack-Request-Timestamp" => ts,
             "X-Slack-Signature" => sig
           }
      assert_response :internal_server_error
    ensure
      ENV["SLACK_SIGNING_SECRET"] = old || SLACK_SECRET
    end
  end

  test "event_callback persists SlackMessage when team is linked" do
    SlackWorkspaceLink.create!(slack_team_id: "T_TEAM123", workspace: @workspace)

    payload = {
      "type" => "event_callback",
      "team_id" => "T_TEAM123",
      "event_id" => "Ev09NY58",
      "api_app_id" => "A123",
      "event" => {
        "type" => "message",
        "channel" => "C012AB",
        "user" => "U01BAD",
        "text" => "hello from slack",
        "ts" => "1355517523.000005",
        "token" => "xoxb-should-not-persist-plaintext"
      }
    }
    body = JSON.generate(payload)
    post_slack_event(body)

    assert_response :success
    assert_equal 1, SlackMessage.where(workspace_id: @workspace.id).count
    sm = SlackMessage.first
    assert_equal "hello from slack", sm.text
    assert_equal "user_typed", sm.intake_kind
    assert_equal "low", sm.trust_tier
    assert_equal "[REDACTED]", sm.raw_payload_json.dig("event", "token")
  end

  test "event_callback skips bot messages" do
    SlackWorkspaceLink.create!(slack_team_id: "T_BOT", workspace: @workspace)
    payload = {
      "type" => "event_callback",
      "team_id" => "T_BOT",
      "event_id" => "Ev2",
      "event" => {
        "type" => "message",
        "subtype" => "bot_message",
        "channel" => "C1",
        "user" => "U1",
        "text" => "bot",
        "ts" => "1355517524.000005"
      }
    }
    post_slack_event(JSON.generate(payload))
    assert_response :success
    assert_equal 0, SlackMessage.count
  end

  test "event_callback unknown team returns 200 without persisting" do
    payload = {
      "type" => "event_callback",
      "team_id" => "T_UNKNOWN",
      "event_id" => "Ev3",
      "event" => {
        "type" => "message",
        "channel" => "C1",
        "user" => "U1",
        "text" => "hi",
        "ts" => "1355517525.000005"
      }
    }
    post_slack_event(JSON.generate(payload))
    assert_response :success
    assert_equal 0, SlackMessage.count
  end

  test "event_callback resolves workspace via SLACK_TEAM_ID env fallback" do
    old_team = ENV["SLACK_TEAM_ID"]
    old_slug = ENV["SLACK_WORKSPACE_SLUG"]
    ENV["SLACK_TEAM_ID"] = "T_ENV_TEAM"
    ENV["SLACK_WORKSPACE_SLUG"] = @workspace.slug

    payload = {
      "type" => "event_callback",
      "team_id" => "T_ENV_TEAM",
      "event_id" => "Ev4",
      "event" => {
        "type" => "message",
        "channel" => "C9",
        "user" => "U9",
        "text" => "via env",
        "ts" => "1355517526.000005"
      }
    }
    post_slack_event(JSON.generate(payload))
    assert_response :success
    assert_equal 1, SlackMessage.where(workspace_id: @workspace.id).count
  ensure
    if old_team
      ENV["SLACK_TEAM_ID"] = old_team
    else
      ENV.delete("SLACK_TEAM_ID")
    end
    if old_slug
      ENV["SLACK_WORKSPACE_SLUG"] = old_slug
    else
      ENV.delete("SLACK_WORKSPACE_SLUG")
    end
  end
end
