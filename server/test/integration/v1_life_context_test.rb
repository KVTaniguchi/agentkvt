require "test_helper"
require "securerandom"

class V1LifeContextTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = Workspace.create!(name: "Default Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
  end

  test "list create update and rename life context entries" do
    put "/v1/life_context/goals", params: {
      life_context_entry: {
        id: SecureRandom.uuid,
        key: "goals",
        value: "Ship v1."
      }
    }, as: :json, headers: workspace_headers

    assert_response :created
    created_body = JSON.parse(response.body)
    assert_equal "goals", created_body.dig("life_context_entry", "key")
    assert_equal "Ship v1.", created_body.dig("life_context_entry", "value")

    get "/v1/life_context", headers: workspace_headers
    assert_response :success
    assert_equal 1, JSON.parse(response.body).fetch("life_context_entries").length

    put "/v1/life_context/goals", params: {
      life_context_entry: {
        key: "priorities",
        value: "Ship v2."
      }
    }, as: :json, headers: workspace_headers

    assert_response :success
    updated_body = JSON.parse(response.body)
    assert_equal "priorities", updated_body.dig("life_context_entry", "key")
    assert_equal "Ship v2.", updated_body.dig("life_context_entry", "value")
    assert_equal 1, @workspace.life_context_entries.count
    assert_equal "priorities", @workspace.life_context_entries.first.key
  end

  private

  def workspace_headers
    { "X-Workspace-Slug" => @workspace.slug, "ACCEPT" => "application/json" }
  end
end
