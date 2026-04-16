require "test_helper"
require "securerandom"

class V1BootstrapTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = Workspace.create!(name: "Default Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    @family_member = @workspace.family_members.create!(display_name: "Kevin", symbol: "K")
    @workspace.agent_logs.create!(
      phase: "outcome",
      content: "Completed objective task."
    )
    @workspace.life_context_entries.create!(
      key: "goals",
      value: "Ship the backend pivot."
    )
  end

  test "bootstrap returns workspace snapshot" do
    get "/v1/bootstrap", headers: workspace_headers

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal @workspace.slug, body.dig("workspace", "slug")
    assert_equal 1, body["family_members"].length
    assert_equal 1, body["agent_logs"].length
    assert_equal 1, body["life_context_entries"].length
    assert_equal 1, body["recent_agent_log_count"]
  end

  private

  def workspace_headers
    { "X-Workspace-Slug" => @workspace.slug, "ACCEPT" => "application/json" }
  end
end
