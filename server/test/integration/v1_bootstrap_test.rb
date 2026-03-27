require "test_helper"
require "securerandom"

class V1BootstrapTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = Workspace.create!(name: "Default Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
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
    get "/v1/bootstrap", headers: workspace_headers

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal @workspace.slug, body.dig("workspace", "slug")
    assert_equal 1, body["family_members"].length
    assert_equal 1, body["missions"].length
    assert_equal 0, body["pending_action_items_count"]
  end

  private

  def workspace_headers
    { "X-Workspace-Slug" => @workspace.slug, "ACCEPT" => "application/json" }
  end
end
