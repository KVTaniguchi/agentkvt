require "test_helper"

class V1AgentEndpointsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = Workspace.create!(name: "Default Workspace", slug: "default")
    @mission = @workspace.missions.create!(
      mission_name: "Tech Job Scout",
      system_prompt: "Create one action item.",
      trigger_schedule: "daily|21:05",
      allowed_mcp_tools: ["write_action_item"],
      is_enabled: true
    )
  end

  test "agent can fetch due missions and write results" do
    travel_to Time.zone.parse("2026-03-27 21:05:00 UTC") do
      get "/v1/agent/due_missions", params: { at: Time.current.iso8601 }, as: :json
      assert_response :success
      assert_equal 1, JSON.parse(response.body).fetch("due_missions").length

      post "/v1/agent/missions/#{@mission.id}/action_items", params: {
        action_item: {
          title: "Review Example Co role",
          system_intent: "url.open",
          payload_json: { url: "https://example.com/jobs/1" }
        }
      }, as: :json
      assert_response :created

      post "/v1/agent/missions/#{@mission.id}/logs", params: {
        agent_log: {
          phase: "outcome",
          content: "Created an action item."
        }
      }, as: :json
      assert_response :created

      post "/v1/agent/missions/#{@mission.id}/mark_run", params: {
        ran_at: Time.current.iso8601
      }, as: :json
      assert_response :success
    end

    assert_equal 1, @workspace.action_items.count
    assert_equal 1, @workspace.agent_logs.count
    assert_not_nil @mission.reload.last_run_at
  end
end
