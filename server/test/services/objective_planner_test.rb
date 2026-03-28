require "test_helper"
require "securerandom"

class ObjectivePlannerTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Test Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    @objective = @workspace.objectives.create!(goal: "Plan a San Diego trip", status: "active")
  end

  test "creates up to 5 tasks from a valid JSON array response" do
    raw_json = JSON.generate([
      { "description" => "Search for flights from SFO to SAN" },
      { "description" => "Compare hotel options near Gaslamp Quarter" },
      { "description" => "Check car rental prices" },
      { "description" => "Look up local restaurants" },
      { "description" => "Find things to do near the beach" },
      { "description" => "This sixth one should be dropped" }
    ])

    tasks = ObjectivePlanner.new(client: stub_client(raw_json)).call(@objective)

    assert_equal 5, tasks.length
    assert_equal "Search for flights from SFO to SAN", tasks.first.description
    assert tasks.all? { |t| t.status == "pending" }
    assert_equal 5, @objective.reload.tasks.count
  end

  test "skips entries with blank description" do
    raw_json = JSON.generate([
      { "description" => "Valid task" },
      { "description" => "" },
      { "description" => "   " }
    ])

    tasks = ObjectivePlanner.new(client: stub_client(raw_json)).call(@objective)

    assert_equal 1, tasks.length
    assert_equal "Valid task", tasks.first.description
  end

  test "returns empty array and logs on JSON parse error" do
    tasks = ObjectivePlanner.new(client: stub_client("not json at all")).call(@objective)

    assert_equal [], tasks
    assert_equal 0, @objective.reload.tasks.count
  end

  test "returns empty array when response is a JSON object instead of array" do
    raw_json = JSON.generate({ "description" => "Forgot to wrap in array" })
    tasks    = ObjectivePlanner.new(client: stub_client(raw_json)).call(@objective)

    assert_equal [], tasks
    assert_equal 0, @objective.reload.tasks.count
  end

  test "returns empty array when the client raises" do
    raising_client = Object.new
    raising_client.define_singleton_method(:chat) { |**_| raise "connection refused" }

    tasks = ObjectivePlanner.new(client: raising_client).call(@objective)

    assert_equal [], tasks
  end

  private

  # Returns a minimal duck-typed Ollama client that always returns +response+.
  def stub_client(response)
    client = Object.new
    client.define_singleton_method(:chat) { |**_kwargs| response }
    client
  end
end
