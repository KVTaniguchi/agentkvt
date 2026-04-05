require "test_helper"
require "securerandom"

class V1AgentLogsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = Workspace.create!(name: "Default Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    @workspace.agent_logs.create!(
      phase: "tool_result",
      content: "Created ActionItem: Review Example Co role (url.open)",
      metadata_json: { "tool_name" => "write_action_item" }
    )
  end

  test "list agent logs with tool metadata" do
    get "/v1/agent_logs", headers: workspace_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body.fetch("agent_logs").length
    assert_equal "write_action_item", body.dig("agent_logs", 0, "tool_name")
  end

  private

  def workspace_headers
    { "X-Workspace-Slug" => @workspace.slug, "ACCEPT" => "application/json" }
  end
end
