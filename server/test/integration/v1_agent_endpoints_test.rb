require "test_helper"
require "securerandom"

class V1AgentEndpointsTest < ActionDispatch::IntegrationTest
  setup do
    @previous_agent_token = ENV["AGENTKVT_AGENT_TOKEN"]
    ENV["AGENTKVT_AGENT_TOKEN"] = "test-agent-token"
    @workspace = Workspace.create!(name: "Default Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
  end

  teardown do
    ENV["AGENTKVT_AGENT_TOKEN"] = @previous_agent_token
  end

  test "agent log endpoint requires a valid bearer token when configured" do
    post "/v1/agent/logs",
         params: { agent_log: { phase: "worker_claim", content: "Denied" } },
         as: :json, headers: workspace_headers

    assert_response :unauthorized
  end

  test "agent can post a log and it is persisted to the workspace" do
    post "/v1/agent/logs",
         params: {
           agent_log: {
             phase: "outcome",
             content: "Finished scanning for action items.",
             metadata_json: { worker_label: "objective-worker-1" }
           }
         },
         as: :json, headers: agent_headers

    assert_response :created
    assert_equal 1, @workspace.agent_logs.count
    assert_equal "outcome", @workspace.agent_logs.first.phase
  end

  private

  def workspace_headers
    { "X-Workspace-Slug" => @workspace.slug, "ACCEPT" => "application/json" }
  end

  def agent_headers
    workspace_headers.merge("Authorization" => "Bearer test-agent-token")
  end
end
