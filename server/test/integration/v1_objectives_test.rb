require "test_helper"
require "securerandom"

class V1ObjectivesTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = Workspace.create!(name: "Test Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
  end

  # ── index ──────────────────────────────────────────────────────────────────

  test "index returns empty list when no objectives exist" do
    get "/v1/objectives", headers: workspace_headers
    assert_response :success
    assert_equal [], JSON.parse(response.body)["objectives"]
  end

  test "index returns objectives ordered by priority desc then created_at desc" do
    @workspace.objectives.create!(goal: "Low priority", status: "pending", priority: 0)
    @workspace.objectives.create!(goal: "High priority", status: "active", priority: 5)

    get "/v1/objectives", headers: workspace_headers
    assert_response :success

    goals = JSON.parse(response.body)["objectives"].map { |o| o["goal"] }
    assert_equal "High priority", goals.first
  end

  test "index serializes expected fields" do
    @workspace.objectives.create!(goal: "Plan beach trip", status: "active", priority: 1)

    get "/v1/objectives", headers: workspace_headers
    assert_response :success

    obj = JSON.parse(response.body)["objectives"].first
    assert_not_nil obj["id"]
    assert_equal "Plan beach trip", obj["goal"]
    assert_equal "active",          obj["status"]
    assert_equal 1,                 obj["priority"]
    assert_not_nil obj["created_at"]
    assert_not_nil obj["updated_at"]
  end

  # ── create ─────────────────────────────────────────────────────────────────

  test "create with pending status persists objective and skips ObjectivePlanner" do
    # Use a planner stub that raises if called — confirms it's never invoked.
    with_stubbed_planner(raises: true) do
      post "/v1/objectives",
           params: { objective: { goal: "Explore new coffee shop", status: "pending" } },
           as: :json, headers: workspace_headers
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "Explore new coffee shop", body.dig("objective", "goal")
    assert_equal "pending",                 body.dig("objective", "status")
    assert_equal 0, @workspace.objectives.first.tasks.count
  end

  test "create with active status calls ObjectivePlanner" do
    # Stub the planner so no Ollama connection is needed; just verify it is called.
    planner_called_with = nil
    with_stubbed_planner do |stub|
      stub.define_singleton_method(:call) do |obj|
        planner_called_with = obj
        []
      end

      post "/v1/objectives",
           params: { objective: { goal: "Research local gyms", status: "active" } },
           as: :json, headers: workspace_headers
    end

    assert_response :created
    assert_not_nil planner_called_with
    assert_equal "Research local gyms", planner_called_with.goal
  end

  test "create defaults priority to 0 when omitted" do
    with_stubbed_planner do
      post "/v1/objectives",
           params: { objective: { goal: "Quick idea", status: "pending" } },
           as: :json, headers: workspace_headers
    end

    assert_response :created
    assert_equal 0, JSON.parse(response.body).dig("objective", "priority")
  end

  test "create rejects unknown status" do
    post "/v1/objectives",
         params: { objective: { goal: "Whatever", status: "bogus" } },
         as: :json, headers: workspace_headers

    assert_response :unprocessable_entity
  end

  test "create rejects missing goal" do
    post "/v1/objectives",
         params: { objective: { status: "pending" } },
         as: :json, headers: workspace_headers

    assert_response :unprocessable_entity
  end

  # ── show ───────────────────────────────────────────────────────────────────

  test "show returns objective with nested tasks and snapshots" do
    objective = @workspace.objectives.create!(goal: "Book flights", status: "active", priority: 2)
    task      = objective.tasks.create!(description: "Search prices", status: "in_progress")
    _snapshot = objective.research_snapshots.create!(
      key: "cheapest_fare", value: "$299", task: task, checked_at: Time.current
    )

    get "/v1/objectives/#{objective.id}", headers: workspace_headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal objective.id.to_s, body.dig("objective", "id")
    assert_equal 1,                 body["tasks"].length
    assert_equal "Search prices",   body["tasks"].first["description"]
    assert_equal 1,                 body["research_snapshots"].length
    assert_equal "cheapest_fare",   body["research_snapshots"].first["key"]
    assert_equal "$299",            body["research_snapshots"].first["value"]
    assert_not_nil                  body["research_snapshots"].first["task_id"]
  end

  test "show returns 404 for unknown objective" do
    get "/v1/objectives/#{SecureRandom.uuid}", headers: workspace_headers
    assert_response :not_found
  end

  test "show does not expose another workspace's objective" do
    other     = Workspace.create!(name: "Other", slug: "other-#{SecureRandom.hex(4)}")
    objective = other.objectives.create!(goal: "Secret plan", status: "pending")

    get "/v1/objectives/#{objective.id}", headers: workspace_headers
    assert_response :not_found
  end

  # ── update ─────────────────────────────────────────────────────────────────

  test "update changes goal and returns serialized objective" do
    objective = @workspace.objectives.create!(goal: "Old goal", status: "active", priority: 1)

    patch "/v1/objectives/#{objective.id}",
          params: { objective: { goal: "New goal", status: "active", priority: 1 } },
          as: :json, headers: workspace_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "New goal", body.dig("objective", "goal")
    assert_equal "active",   body.dig("objective", "status")
    assert_equal 1,          body.dig("objective", "priority")
    assert_equal "New goal", objective.reload.goal
  end

  test "update from pending to active invokes ObjectivePlanner when there are no tasks yet" do
    planner_called = false
    objective = @workspace.objectives.create!(goal: "Activate me", status: "pending", priority: 0)

    with_stubbed_planner do |stub|
      stub.define_singleton_method(:call) do |obj|
        planner_called = true
        assert_equal objective.id, obj.id
        []
      end

      patch "/v1/objectives/#{objective.id}",
            params: { objective: { goal: "Activate me", status: "active", priority: 0 } },
            as: :json, headers: workspace_headers
    end

    assert_response :success
    assert planner_called, "ObjectivePlanner should run when activating a pending objective with no tasks"
  end

  test "update from pending to active does not invoke ObjectivePlanner when tasks already exist" do
    call_count = 0
    objective = @workspace.objectives.create!(goal: "Already has work", status: "pending", priority: 0)
    objective.tasks.create!(description: "Existing task", status: "pending")

    with_stubbed_planner do |stub|
      stub.define_singleton_method(:call) do |_obj|
        call_count += 1
        []
      end

      patch "/v1/objectives/#{objective.id}",
            params: { objective: { goal: "Already has work", status: "active", priority: 0 } },
            as: :json, headers: workspace_headers
    end

    assert_response :success
    assert_equal 0, call_count
  end

  test "update returns 404 for unknown objective" do
    patch "/v1/objectives/#{SecureRandom.uuid}",
          params: { objective: { goal: "X", status: "pending", priority: 0 } },
          as: :json, headers: workspace_headers

    assert_response :not_found
  end

  test "update rejects empty goal" do
    objective = @workspace.objectives.create!(goal: "Has text", status: "active", priority: 1)

    patch "/v1/objectives/#{objective.id}",
          params: { objective: { goal: "", status: "active", priority: 1 } },
          as: :json, headers: workspace_headers

    assert_response :unprocessable_entity
    assert_equal "Has text", objective.reload.goal
  end

  test "update does not modify another workspace objective" do
    other     = Workspace.create!(name: "Other", slug: "other-#{SecureRandom.hex(4)}")
    objective = other.objectives.create!(goal: "Secret", status: "pending", priority: 0)

    patch "/v1/objectives/#{objective.id}",
          params: { objective: { goal: "Hacked", status: "active", priority: 9 } },
          as: :json, headers: workspace_headers

    assert_response :not_found
    assert_equal "Secret", objective.reload.goal
  end

  # ── destroy ──────────────────────────────────────────────────────────────

  test "destroy removes objective and returns no content" do
    objective = @workspace.objectives.create!(goal: "Temporary", status: "pending", priority: 0)

    delete "/v1/objectives/#{objective.id}", headers: workspace_headers

    assert_response :no_content
    assert_raises(ActiveRecord::RecordNotFound) { objective.reload }
  end

  test "destroy returns 404 for unknown objective" do
    delete "/v1/objectives/#{SecureRandom.uuid}", headers: workspace_headers

    assert_response :not_found
  end

  test "destroy does not delete another workspace objective" do
    other     = Workspace.create!(name: "Other", slug: "other-#{SecureRandom.hex(4)}")
    objective = other.objectives.create!(goal: "Keep me", status: "pending")

    delete "/v1/objectives/#{objective.id}", headers: workspace_headers

    assert_response :not_found
    assert_equal "Keep me", objective.reload.goal
  end

  private

  def workspace_headers
    { "X-Workspace-Slug" => @workspace.slug, "ACCEPT" => "application/json" }
  end

  # Replaces ObjectivePlanner.new with a stub for the duration of the block.
  # Default stub is a no-op that returns [].
  # If +raises: true+, the stub raises if #call is invoked (use to assert it's never called).
  # Yields the stub so the caller can override #call via define_singleton_method.
  def with_stubbed_planner(raises: false)
    stub = Object.new
    if raises
      stub.define_singleton_method(:call) { |_obj| raise "ObjectivePlanner#call should not have been called" }
    else
      stub.define_singleton_method(:call) { |_obj| [] }
    end
    original = ObjectivePlanner.method(:new)
    ObjectivePlanner.define_singleton_method(:new) { |**_kw| stub }
    yield stub
  ensure
    ObjectivePlanner.define_singleton_method(:new, &original)
  end
end
