require "test_helper"

class V1BootstrapTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = Workspace.create!(name: "Default Workspace", slug: "default")
    @family_member = @workspace.family_members.create!(display_name: "Kevin", symbol: "K")
    @workspace.missions.create!(
      mission_name: "Tech Job Scout",
      system_prompt: "Create one action item.",
      trigger_schedule: "daily|09:00",
      allowed_mcp_tools: ["write_action_item"],
      owner_profile: @family_member
    )
  end

  test "bootstrap returns workspace snapshot" do
    get "/v1/bootstrap"

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal "default", body.dig("workspace", "slug")
    assert_equal 1, body["family_members"].length
    assert_equal 1, body["missions"].length
    assert_equal 0, body["pending_action_items_count"]
  end
end
