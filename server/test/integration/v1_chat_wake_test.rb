# frozen_string_literal: true

require "test_helper"

class V1ChatWakeTest < ActionDispatch::IntegrationTest
  setup do
    @previous_agent_token = ENV["AGENTKVT_AGENT_TOKEN"]
    ENV["AGENTKVT_AGENT_TOKEN"] = "test-agent-token"
    @workspace = Workspace.create!(name: "Chat Wake", slug: "workspace-#{SecureRandom.hex(4)}")
  end

  teardown do
    ENV["AGENTKVT_AGENT_TOKEN"] = @previous_agent_token
  end

  test "POST chat_wake sets flag" do
    post "/v1/chat_wake", params: {}, as: :json, headers: workspace_headers
    assert_response :accepted
    assert_not_nil @workspace.reload.chat_wake_requested_at
  end

  test "GET agent chat_wake consumes flag" do
    @workspace.update!(chat_wake_requested_at: Time.zone.parse("2026-03-28 12:00:00 UTC"))

    get "/v1/agent/chat_wake", headers: agent_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["pending"]
    assert_match(/2026-03-28T12:00:00/, body["requested_at"].to_s)
    assert_nil @workspace.reload.chat_wake_requested_at

    get "/v1/agent/chat_wake", headers: agent_headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body["pending"]
    assert_nil body["requested_at"]
  end

  test "agent chat_wake requires bearer token when configured" do
    get "/v1/agent/chat_wake", headers: workspace_headers
    assert_response :unauthorized
  end

  private

  def workspace_headers
    { "X-Workspace-Slug" => @workspace.slug, "ACCEPT" => "application/json" }
  end

  def agent_headers
    workspace_headers.merge("Authorization" => "Bearer test-agent-token")
  end
end
