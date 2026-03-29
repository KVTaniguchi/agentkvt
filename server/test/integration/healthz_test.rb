require "test_helper"

class HealthzTest < ActionDispatch::IntegrationTest
  test "returns service metadata and database readiness" do
    get "/healthz"
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal true, body["ok"]
    assert_equal "agentkvt-server", body["service"]
    assert body["time"].present?

    db = body["database"]
    assert_equal true, db["connected"]
    assert_equal true, db["objectives_table"]
    assert_equal true, body["ready"]
  end
end
