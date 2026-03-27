require "test_helper"

class V1ActionItemsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = Workspace.create!(name: "Default Workspace", slug: "default")
    @action_item = @workspace.action_items.create!(
      title: "Review Orlando hotels",
      system_intent: "url.open",
      payload_json: { "url" => "https://example.com/hotels" },
      relevance_score: 0.9
    )
  end

  test "list and handle action items" do
    get "/v1/action_items"
    assert_response :success
    assert_equal 1, JSON.parse(response.body).fetch("action_items").length

    post "/v1/action_items/#{@action_item.id}/handle", as: :json
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal true, body.dig("action_item", "is_handled")
    assert_not_nil body.dig("action_item", "handled_at")
  end
end
