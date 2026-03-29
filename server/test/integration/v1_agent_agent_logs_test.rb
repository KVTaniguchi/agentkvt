require "test_helper"
require "securerandom"

class V1AgentAgentLogsTest < ActionDispatch::IntegrationTest
  setup do
    @previous_agent_token = ENV["AGENTKVT_AGENT_TOKEN"]
    ENV["AGENTKVT_AGENT_TOKEN"] = "test-agent-token"
    @workspace = Workspace.create!(name: "Test Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
  end

  teardown do
    ENV["AGENTKVT_AGENT_TOKEN"] = @previous_agent_token
  end

  test "creates a workspace-scoped agent log with metadata" do
    post "/v1/agent/logs",
         params: {
           agent_log: {
             phase: "worker_claim",
             content: "Objective worker claimed a board item",
             metadata_json: {
               mission_name: "Objective Worker alpha",
               objective_id: SecureRandom.uuid,
               worker_label: "objective-worker-1"
             }
           }
         },
         as: :json, headers: agent_headers

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "worker_claim", body.dig("agent_log", "phase")
    assert_equal "Objective Worker alpha", body.dig("agent_log", "mission_name")
    assert_equal "objective-worker-1", body.dig("agent_log", "metadata_json", "worker_label")
    assert_equal 1, @workspace.agent_logs.count
  end

  test "requires a valid bearer token" do
    post "/v1/agent/logs",
         params: { agent_log: { phase: "worker_claim", content: "Denied" } },
         as: :json, headers: workspace_headers

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
