require "test_helper"
require "securerandom"

class V1FamilyMembersTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = Workspace.create!(name: "Default Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
  end

  test "create and index family members" do
    member_id = SecureRandom.uuid

    post "/v1/family_members", params: {
      family_member: {
        id: member_id,
        display_name: "Kevin",
        symbol: "K"
      }
    }, as: :json, headers: workspace_headers

    assert_response :created
    assert_equal member_id, JSON.parse(response.body).dig("family_member", "id")

    get "/v1/family_members", headers: workspace_headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 1, body.fetch("family_members").length
    assert_equal "Kevin", body.fetch("family_members").first.fetch("display_name")
  end

  private

  def workspace_headers
    { "X-Workspace-Slug" => @workspace.slug, "ACCEPT" => "application/json" }
  end
end
