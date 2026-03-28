require "test_helper"
require "securerandom"

class V1MissionsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = Workspace.create!(name: "Default Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    @family_member = @workspace.family_members.create!(display_name: "Kevin", symbol: "K")
  end

  test "create index update and destroy missions" do
    post "/v1/missions", params: {
      mission: {
        mission_name: "Universal Orlando Family Trip",
        system_prompt: "Plan a family trip.",
        trigger_schedule: "daily|21:05",
        allowed_mcp_tools: ["write_action_item"],
        owner_profile_id: @family_member.id
      }
    }, as: :json, headers: workspace_headers

    assert_response :created
    mission_id = JSON.parse(response.body).dig("mission", "id")

    get "/v1/missions", headers: workspace_headers
    assert_response :success
    assert_equal 1, JSON.parse(response.body).fetch("missions").length

    patch "/v1/missions/#{mission_id}", params: {
      mission: {
        trigger_schedule: "daily|21:15",
        is_enabled: false
      }
    }, as: :json, headers: workspace_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "daily|21:15", body.dig("mission", "trigger_schedule")
    assert_equal false, body.dig("mission", "is_enabled")

    delete "/v1/missions/#{mission_id}", headers: workspace_headers
    assert_response :no_content

    get "/v1/missions", headers: workspace_headers
    assert_response :success
    assert_equal 0, JSON.parse(response.body).fetch("missions").length
  end

  test "update creates a missing mission with the requested id" do
    mission_id = SecureRandom.uuid

    patch "/v1/missions/#{mission_id}", params: {
      mission: {
        id: mission_id,
        mission_name: "Imported Local Mission",
        system_prompt: "Import this local mission into the backend.",
        trigger_schedule: "daily|08:00",
        allowed_mcp_tools: ["write_action_item"],
        is_enabled: true
      }
    }, as: :json, headers: workspace_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal mission_id, body.dig("mission", "id")
    assert_equal "Imported Local Mission", body.dig("mission", "mission_name")
    assert_equal 1, @workspace.missions.where(id: mission_id).count
  end

  test "destroy succeeds even when the mission is already missing" do
    delete "/v1/missions/#{SecureRandom.uuid}", headers: workspace_headers
    assert_response :no_content
  end

  private

  def workspace_headers
    { "X-Workspace-Slug" => @workspace.slug, "ACCEPT" => "application/json" }
  end
end
