require "test_helper"
require "securerandom"

class ObjectivePlannerTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Test Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    @objective = @workspace.objectives.create!(goal: "Plan a San Diego trip", status: "active")
  end

  test "creates up to 12 tasks from a valid JSON array response" do
    raw_json = JSON.generate([
      { "description" => "Search for flights from SFO to SAN" },
      { "description" => "Compare hotel options near Gaslamp Quarter" },
      { "description" => "Check car rental prices" },
      { "description" => "Look up local restaurants" },
      { "description" => "Find things to do near the beach" },
      { "description" => "Check weather trends by date range" },
      { "description" => "Compare neighborhood safety and transport access" },
      { "description" => "Build a day-by-day draft itinerary" },
      { "description" => "Estimate total budget with confidence ranges" },
      { "description" => "This eleventh one should still be kept" },
      { "description" => "This twelfth one should still be kept" },
      { "description" => "This thirteenth one should be dropped" }
    ])

    tasks = ObjectivePlanner.new(client: stub_client(raw_json)).call(@objective)

    assert_equal 12, tasks.length
    assert_equal "Search for flights from SFO to SAN", tasks.first.description
    assert tasks.all? { |t| t.status == "pending" }
    assert_equal 12, @objective.reload.tasks.count
  end

  test "skips entries with blank description and tops up to minimum task count" do
    raw_json = JSON.generate([
      { "description" => "Valid task" },
      { "description" => "" },
      { "description" => "   " }
    ])

    tasks = ObjectivePlanner.new(client: stub_client(raw_json)).call(@objective)

    assert_operator tasks.length, :>=, 4
    assert_equal "Valid task", tasks.first.description
  end

  test "creates fallback tasks on JSON parse error" do
    tasks = ObjectivePlanner.new(client: stub_client("not json at all")).call(@objective)

    assert_operator tasks.length, :>=, 1
    assert_equal tasks.length, @objective.reload.tasks.count
  end

  test "accepts a wrapped tasks array response" do
    raw_json = JSON.generate({
      "tasks" => [
        { "description" => "Research family-friendly attractions in San Diego" },
        { "description" => "Compare airport transfer options" }
      ]
    })

    tasks = ObjectivePlanner.new(client: stub_client(raw_json)).call(@objective)

    assert_equal 2, tasks.length
    assert_equal "Research family-friendly attractions in San Diego", tasks.first.description
    assert_equal 2, @objective.reload.tasks.count
  end

  test "tops up with heuristic tasks when llm returns too few for a complex objective" do
    objective = @workspace.objectives.create!(
      goal: "Plan a two-week Japan trip with flights, lodging, city-to-city transit, day-by-day itinerary, and budget by category.",
      status: "active"
    )
    raw_json = JSON.generate([{ "description" => "Compare flights and arrival airports" }])

    tasks = ObjectivePlanner.new(client: stub_client(raw_json)).call(objective)

    assert_operator tasks.length, :>=, 6
    assert_includes tasks.map(&:description), "Compare flights and arrival airports"
  end

  test "creates fallback tasks when response is a JSON object instead of array" do
    raw_json = JSON.generate({ "description" => "Forgot to wrap in array" })
    tasks    = ObjectivePlanner.new(client: stub_client(raw_json)).call(@objective)

    assert_operator tasks.length, :>=, 1
    assert_equal tasks.length, @objective.reload.tasks.count
  end

  test "creates fallback tasks when the client raises" do
    raising_client = Object.new
    raising_client.define_singleton_method(:chat) { |**_| raise "connection refused" }

    tasks = ObjectivePlanner.new(client: raising_client).call(@objective)

    assert_operator tasks.length, :>=, 1
    assert_equal tasks.length, @objective.reload.tasks.count
  end

  test "creates fallback tasks when LLM returns an empty array" do
    tasks = ObjectivePlanner.new(client: stub_client("[]")).call(@objective)

    assert_operator tasks.length, :>=, 1
    assert_equal tasks.length, @objective.reload.tasks.count
  end

  private

  # Returns a minimal duck-typed Ollama client that always returns +response+.
  def stub_client(response)
    client = Object.new
    client.define_singleton_method(:chat) { |**_kwargs| response }
    client
  end
end
