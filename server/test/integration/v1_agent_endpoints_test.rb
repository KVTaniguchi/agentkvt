require "test_helper"
require "securerandom"

class V1AgentEndpointsTest < ActionDispatch::IntegrationTest
  setup do
    @previous_agent_token = ENV["AGENTKVT_AGENT_TOKEN"]
    ENV["AGENTKVT_AGENT_TOKEN"] = "test-agent-token"
    @workspace = Workspace.create!(name: "Default Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    @mission = @workspace.missions.create!(
      mission_name: "Tech Job Scout",
      system_prompt: "Create one action item.",
      trigger_schedule: "daily|21:05",
      allowed_mcp_tools: ["write_action_item"],
      is_enabled: true
    )
  end

  teardown do
    ENV["AGENTKVT_AGENT_TOKEN"] = @previous_agent_token
  end

  test "mission with write_action_item in tools must mention it in the prompt" do
    bad_mission = @workspace.missions.build(
      mission_name: "Silent Mission",
      system_prompt: "Search for jobs and report back.",
      trigger_schedule: "daily|09:00",
      allowed_mcp_tools: ["write_action_item"],
      is_enabled: true
    )
    assert_not bad_mission.valid?
    assert_includes bad_mission.errors[:system_prompt].join, "write_action_item"
  end

  test "mission with write_action_item in tools saves when prompt references it" do
    good_mission = @workspace.missions.build(
      mission_name: "Good Mission",
      system_prompt: "Search for jobs and call write_action_item with systemIntent url.open for each lead.",
      trigger_schedule: "daily|09:00",
      allowed_mcp_tools: ["write_action_item"],
      is_enabled: true
    )
    assert good_mission.valid?
  end

  test "mission without write_action_item in tools saves regardless of prompt" do
    mission = @workspace.missions.build(
      mission_name: "No Output Mission",
      system_prompt: "Summarize today's news.",
      trigger_schedule: "daily|09:00",
      allowed_mcp_tools: ["web_search_and_fetch"],
      is_enabled: true
    )
    assert mission.valid?
  end

  test "agent endpoints require a valid bearer token when configured" do
    get "/v1/agent/due_missions", params: { at: Time.current.iso8601 }, headers: workspace_headers

    assert_response :unauthorized
  end

  test "agent can fetch due missions and write results" do
    travel_to Time.zone.parse("2026-03-27 21:05:00 UTC") do
      get "/v1/agent/due_missions", params: { at: Time.current.iso8601 }, headers: agent_headers
      assert_response :success
      assert_equal 1, JSON.parse(response.body).fetch("due_missions").length

      post "/v1/agent/missions/#{@mission.id}/action_items", params: {
        action_item: {
          title: "Review Example Co role",
          system_intent: "url.open",
          payload_json: { url: "https://example.com/jobs/1" }
        }
      }, as: :json, headers: agent_headers
      assert_response :created

      post "/v1/agent/missions/#{@mission.id}/logs", params: {
        agent_log: {
          phase: "outcome",
          content: "Created an action item."
        }
      }, as: :json, headers: agent_headers
      assert_response :created

      post "/v1/agent/missions/#{@mission.id}/mark_run", params: {
        ran_at: Time.current.iso8601
      }, as: :json, headers: agent_headers
      assert_response :success
    end

    assert_equal 1, @workspace.action_items.count
    assert_equal 1, @workspace.agent_logs.count
    assert_not_nil @mission.reload.last_run_at
  end

  private

  def workspace_headers
    { "X-Workspace-Slug" => @workspace.slug, "ACCEPT" => "application/json" }
  end

  def agent_headers
    workspace_headers.merge("Authorization" => "Bearer test-agent-token")
  end
end
