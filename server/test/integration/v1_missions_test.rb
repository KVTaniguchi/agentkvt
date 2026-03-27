require "test_helper"

class V1MissionsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = Workspace.create!(name: "Default Workspace", slug: "default")
    @family_member = @workspace.family_members.create!(display_name: "Kevin", symbol: "K")
  end

  test "create index and update missions" do
    post "/v1/missions", params: {
      mission: {
        mission_name: "Universal Orlando Family Trip",
        system_prompt: "Plan a family trip.",
        trigger_schedule: "daily|21:05",
        allowed_mcp_tools: ["write_action_item"],
        owner_profile_id: @family_member.id
      }
    }, as: :json

    assert_response :created
    mission_id = JSON.parse(response.body).dig("mission", "id")

    get "/v1/missions"
    assert_response :success
    assert_equal 1, JSON.parse(response.body).fetch("missions").length

    patch "/v1/missions/#{mission_id}", params: {
      mission: {
        trigger_schedule: "daily|21:15",
        is_enabled: false
      }
    }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "daily|21:15", body.dig("mission", "trigger_schedule")
    assert_equal false, body.dig("mission", "is_enabled")
  end
end
