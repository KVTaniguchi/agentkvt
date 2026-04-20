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
    assert tasks.all? { |t| t.status == "proposed" }
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

    assert_operator tasks.length, :>=, 2
    assert_equal "Research family-friendly attractions in San Diego", tasks.first.description
    assert_equal tasks.length, @objective.reload.tasks.count
  end

  test "persists execution contract fields for action tasks" do
    raw_json = JSON.generate([
      {
        "description" => "Use the site_scout tool to add the best in-stock filter 3-pack to the Target cart and confirm the subtotal.",
        "task_kind" => "action",
        "allowed_tool_ids" => ["site_scout"],
        "required_capabilities" => ["objective_research", "site_scout"],
        "done_when" => "An objective snapshot records the cart subtotal or the blocker preventing checkout."
      }
    ])

    task = ObjectivePlanner.new(client: stub_client(raw_json)).call(@objective).first

    assert_equal "action", task.task_kind
    assert_includes task.allowed_tool_ids, "site_scout"
    assert_includes task.allowed_tool_ids, "write_objective_snapshot"
    assert_includes task.required_capabilities, "site_scout"
    assert_equal "An objective snapshot records the cart subtotal or the blocker preventing checkout.", task.done_when
  end

  test "tops up with heuristic tasks when llm returns too few for a complex objective" do
    objective = @workspace.objectives.create!(
      goal: "Plan a two-week Japan trip with flights, hotel lodging, city-to-city transit, day-by-day itinerary, and budget by category.",
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

  test "rewrites generic llm tasks with objective-aware follow-through" do
    objective = @workspace.objectives.create!(
      goal: "Help me plan a realistic first day at Universal Orlando",
      status: "active",
      objective_kind: "trip_planning",
      brief_json: {
        context: ["July 11 arrival around 11 AM for a group of 8"],
        success_criteria: ["Have a realistic first-day itinerary"],
        constraints: ["Avoid impossible park-hopping timing"],
        preferences: ["Prioritize Harry Potter and Super Mario attractions"],
        deliverable: "Recommended first-day itinerary with backup plan",
        open_questions: ["Whether early entry is available"]
      }
    )

    raw_json = JSON.generate([
      { "description" => "Clarify objective scope, assumptions, and success criteria for: #{objective.goal}" },
      { "description" => "Research and compare the top options relevant to this objective" },
      { "description" => "Compare official park hours and early-entry windows for July 11" }
    ])

    tasks = ObjectivePlanner.new(client: stub_client(raw_json)).call(objective)
    descriptions = tasks.map(&:description)

    assert_includes descriptions, "Compare official park hours and early-entry windows for July 11"
    assert descriptions.none? { |description| description.start_with?("Clarify objective scope") }
    assert descriptions.any? { |description| description.include?("Recommended first-day itinerary with backup plan") }
  end

  test "fallback tasks stay focused on deliverable and constraints" do
    objective = @workspace.objectives.create!(
      goal: "Help me plan a household purchasing decision",
      status: "active",
      objective_kind: "household_planning",
      brief_json: {
        context: ["Need to replace a washer and dryer this month"],
        success_criteria: ["Pick a reliable option under budget"],
        constraints: ["Stay under $1,500 installed"],
        preferences: ["Prefer simple controls and low repair risk"],
        deliverable: "Recommendation with next step and backup option",
        open_questions: []
      }
    )

    raising_client = Object.new
    raising_client.define_singleton_method(:chat) { |**_| raise "connection refused" }

    tasks = ObjectivePlanner.new(client: raising_client).call(objective)
    descriptions = tasks.map(&:description)

    assert descriptions.any? { |description| description.include?("Recommendation with next step and backup option") }
    assert descriptions.any? { |description| description.include?("Stay under $1,500 installed") }
    assert descriptions.none? { |description| description.start_with?("Clarify objective scope") }
  end

  test "planner prompt includes objective brief metadata when present" do
    captured_messages = nil
    objective = @workspace.objectives.create!(
      goal: "Help me make a budget",
      status: "active",
      objective_kind: "budget",
      brief_json: {
        context: ["Monthly family budget for a four-person household"],
        success_criteria: ["Save at least $500 per month"],
        constraints: ["Keep restaurant spending under $300"],
        preferences: ["Simple category structure"],
        deliverable: "Monthly category budget with recommended caps",
        open_questions: []
      }
    )

    client = Object.new
    client.define_singleton_method(:chat) do |messages:, **_kwargs|
      captured_messages = messages
      JSON.generate([{ "description" => "Build a monthly category budget" }])
    end

    ObjectivePlanner.new(client: client).call(objective)

    planning_input = captured_messages.last.fetch(:content)
    assert_includes planning_input, "Objective archetype: Budget"
    assert_includes planning_input, "Success criteria:"
    assert_includes planning_input, "Constraints:"
    assert_includes planning_input, "Deliverable:"
  end

  private

  # Returns a minimal duck-typed Ollama client that always returns +response+.
  def stub_client(response)
    client = Object.new
    client.define_singleton_method(:chat) { |**_kwargs| response }
    client
  end
end
