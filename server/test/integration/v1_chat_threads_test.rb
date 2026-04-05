require "test_helper"
require "securerandom"

class V1ChatThreadsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = Workspace.create!(name: "Chat Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    @member = @workspace.family_members.create!(display_name: "Kevin", symbol: "K", source: "ios")
  end

  test "create thread, send message, index threads, and show messages" do
    thread_id = SecureRandom.uuid
    message_id = SecureRandom.uuid

    post "/v1/chat_threads", params: {
      chat_thread: {
        id: thread_id,
        title: "Family Assistant",
        created_by_profile_id: @member.id
      }
    }, as: :json, headers: workspace_headers

    assert_response :created
    assert_equal thread_id, JSON.parse(response.body).dig("chat_thread", "id")

    post "/v1/chat_threads/#{thread_id}/chat_messages", params: {
      chat_message: {
        id: message_id,
        content: "What should I work on next?",
        author_profile_id: @member.id
      }
    }, as: :json, headers: workspace_headers

    assert_response :created
    message_body = JSON.parse(response.body).fetch("chat_message")
    assert_equal message_id, message_body.fetch("id")
    assert_equal "pending", message_body.fetch("status")
    assert_not_nil @workspace.reload.chat_wake_requested_at

    get "/v1/chat_threads", headers: workspace_headers
    assert_response :success

    index_body = JSON.parse(response.body)
    assert_equal 1, index_body.fetch("chat_threads").length
    thread_payload = index_body.fetch("chat_threads").first
    assert_equal "Family Assistant", thread_payload.fetch("title")
    assert_match(/What should I work on next/, thread_payload.fetch("latest_message_preview"))
    assert_equal 1, thread_payload.fetch("pending_message_count")

    get "/v1/chat_threads/#{thread_id}", headers: workspace_headers
    assert_response :success

    detail_body = JSON.parse(response.body)
    assert_equal thread_id, detail_body.dig("chat_thread", "id")
    assert_equal 1, detail_body.fetch("chat_messages").length
    assert_equal "user", detail_body.fetch("chat_messages").first.fetch("role")
  end

  private

  def workspace_headers
    { "X-Workspace-Slug" => @workspace.slug, "ACCEPT" => "application/json" }
  end
end
