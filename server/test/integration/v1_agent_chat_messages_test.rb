require "test_helper"
require "securerandom"

class V1AgentChatMessagesTest < ActionDispatch::IntegrationTest
  setup do
    @previous_agent_token = ENV["AGENTKVT_AGENT_TOKEN"]
    ENV["AGENTKVT_AGENT_TOKEN"] = "test-agent-token"

    @workspace = Workspace.create!(name: "Agent Chat Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    @member = @workspace.family_members.create!(display_name: "Kevin", symbol: "K", source: "ios")
    @thread = @workspace.chat_threads.create!(title: "Family Assistant", created_by_profile: @member)
  end

  teardown do
    ENV["AGENTKVT_AGENT_TOKEN"] = @previous_agent_token
  end

  test "claim_next marks the next message processing and complete writes assistant reply" do
    message = @thread.chat_messages.create!(
      role: "user",
      content: "Can you summarize the plan?",
      status: "pending",
      author_profile: @member
    )

    post "/v1/agent/chat_messages/claim_next", headers: agent_headers
    assert_response :success

    claim_body = JSON.parse(response.body)
    assert_equal true, claim_body.fetch("pending")
    assert_equal message.id.to_s, claim_body.dig("chat_message", "id")
    assert_equal "processing", claim_body.dig("chat_message", "status")
    assert_equal "processing", message.reload.status

    post "/v1/agent/chat_messages/#{message.id}/complete", params: {
      assistant_message: {
        content: "Start with the highest-priority objective and review the latest research."
      }
    }, as: :json, headers: agent_headers

    assert_response :success
    completion_body = JSON.parse(response.body)
    assert_equal "completed", completion_body.dig("chat_message", "status")
    assert_equal "assistant", completion_body.dig("assistant_message", "role")
    assert_equal 2, @thread.chat_messages.count
    assert_equal "completed", message.reload.status
  end

  test "fail marks the claimed message failed with an error" do
    message = @thread.chat_messages.create!(
      role: "user",
      content: "This will fail",
      status: "pending",
      author_profile: @member
    )

    post "/v1/agent/chat_messages/claim_next", headers: agent_headers
    assert_response :success

    post "/v1/agent/chat_messages/#{message.id}/fail", params: {
      chat_message: {
        error_message: "Ollama timed out"
      }
    }, as: :json, headers: agent_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "failed", body.dig("chat_message", "status")
    assert_equal "Ollama timed out", message.reload.error_message
  end

  private

  def workspace_headers
    { "X-Workspace-Slug" => @workspace.slug, "ACCEPT" => "application/json" }
  end

  def agent_headers
    workspace_headers.merge("Authorization" => "Bearer test-agent-token")
  end
end
