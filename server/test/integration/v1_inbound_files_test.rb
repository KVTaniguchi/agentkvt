require "test_helper"
require "securerandom"
require "base64"

class V1InboundFilesTest < ActionDispatch::IntegrationTest
  setup do
    @previous_agent_token = ENV["AGENTKVT_AGENT_TOKEN"]
    ENV["AGENTKVT_AGENT_TOKEN"] = "test-agent-token"

    @workspace = Workspace.create!(name: "Inbound Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    @member = @workspace.family_members.create!(display_name: "Kevin", symbol: "K", source: "ios")
  end

  teardown do
    ENV["AGENTKVT_AGENT_TOKEN"] = @previous_agent_token
  end

  test "create and index inbound files, then mark them processed from the agent endpoint" do
    file_id = SecureRandom.uuid
    encoded = Base64.strict_encode64("hello from iphone")

    post "/v1/inbound_files", params: {
      inbound_file: {
        id: file_id,
        file_name: "notes.txt",
        content_type: "text/plain",
        uploaded_by_profile_id: @member.id,
        file_base64: encoded
      }
    }, as: :json, headers: workspace_headers

    assert_response :created
    create_body = JSON.parse(response.body).fetch("inbound_file")
    assert_equal file_id, create_body.fetch("id")
    assert_equal 17, create_body.fetch("byte_size")
    assert_equal false, create_body.fetch("is_processed")

    get "/v1/inbound_files", headers: workspace_headers
    assert_response :success
    list_body = JSON.parse(response.body)
    assert_equal 1, list_body.fetch("inbound_files").length
    assert_nil list_body.fetch("inbound_files").first["file_base64"]

    get "/v1/agent/inbound_files", headers: agent_headers
    assert_response :success
    agent_list_body = JSON.parse(response.body)
    assert_equal 1, agent_list_body.fetch("inbound_files").length
    assert_equal encoded, agent_list_body.fetch("inbound_files").first.fetch("file_base64")

    post "/v1/agent/inbound_files/#{file_id}/mark_processed", headers: agent_headers
    assert_response :success
    assert_equal true, @workspace.inbound_files.find(file_id).is_processed
  end

  test "create rejects invalid base64 payloads" do
    post "/v1/inbound_files", params: {
      inbound_file: {
        file_name: "bad.txt",
        file_base64: "not-valid-base64"
      }
    }, as: :json, headers: workspace_headers

    assert_response :bad_request
  end

  private

  def workspace_headers
    { "X-Workspace-Slug" => @workspace.slug, "ACCEPT" => "application/json" }
  end

  def agent_headers
    workspace_headers.merge("Authorization" => "Bearer test-agent-token")
  end
end
