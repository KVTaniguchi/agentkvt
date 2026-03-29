require "test_helper"
require "securerandom"

class V1AgentResearchSnapshotsTest < ActionDispatch::IntegrationTest
  setup do
    @previous_agent_token = ENV["AGENTKVT_AGENT_TOKEN"]
    ENV["AGENTKVT_AGENT_TOKEN"] = "test-agent-token"

    @workspace  = Workspace.create!(name: "Test Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    @objective  = @workspace.objectives.create!(goal: "Track mortgage rates", status: "active")
    @task       = @objective.tasks.create!(description: "Fetch current 30-yr rate", status: "in_progress")
  end

  teardown do
    ENV["AGENTKVT_AGENT_TOKEN"] = @previous_agent_token
  end

  # ── first observation ───────────────────────────────────────────────────────

  test "first snapshot observation creates record with no delta" do
    post "/v1/agent/objectives/#{@objective.id}/research_snapshots",
         params: { research_snapshot: { key: "30yr_rate", value: "6.85%" } },
         as: :json, headers: agent_headers

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "30yr_rate", body.dig("research_snapshot", "key")
    assert_equal "6.85%",     body.dig("research_snapshot", "value")
    assert_nil body.dig("research_snapshot", "previous_value")
    assert_nil body.dig("research_snapshot", "delta_note")
  end

  # ── same value upsert ───────────────────────────────────────────────────────

  test "second observation with identical value does not set delta_note" do
    @objective.research_snapshots.create!(
      key: "30yr_rate", value: "6.85%", checked_at: 1.hour.ago
    )

    post "/v1/agent/objectives/#{@objective.id}/research_snapshots",
         params: { research_snapshot: { key: "30yr_rate", value: "6.85%" } },
         as: :json, headers: agent_headers

    assert_response :created
    snapshot = @objective.research_snapshots.find_by!(key: "30yr_rate")
    assert_nil snapshot.delta_note
    assert_nil snapshot.previous_value
    assert_equal 1, @objective.research_snapshots.count
  end

  # ── changed value upsert ────────────────────────────────────────────────────

  test "second observation with changed value sets previous_value and delta_note" do
    @objective.research_snapshots.create!(
      key: "30yr_rate", value: "6.85%", checked_at: 1.hour.ago
    )

    post "/v1/agent/objectives/#{@objective.id}/research_snapshots",
         params: { research_snapshot: { key: "30yr_rate", value: "7.10%" } },
         as: :json, headers: agent_headers

    assert_response :created
    snapshot = @objective.research_snapshots.reload.find_by!(key: "30yr_rate")
    assert_equal "6.85%",  snapshot.previous_value
    assert_match /6\.85%/, snapshot.delta_note
    assert_match /7\.10%/, snapshot.delta_note
  end

  # ── task completion ─────────────────────────────────────────────────────────

  test "supplying task_id marks that task completed with result_summary" do
    post "/v1/agent/objectives/#{@objective.id}/research_snapshots",
         params: {
           task_id: @task.id,
           research_snapshot: { key: "30yr_rate", value: "6.85%" }
         },
         as: :json, headers: agent_headers

    assert_response :created
    @task.reload
    assert_equal "completed", @task.status
    assert_not_nil @task.result_summary
  end

  test "supplying task_id with mark_task_completed false keeps the task in progress" do
    post "/v1/agent/objectives/#{@objective.id}/research_snapshots",
         params: {
           task_id: @task.id,
           mark_task_completed: false,
           research_snapshot: { key: "30yr_rate", value: "6.85%" }
         },
         as: :json, headers: agent_headers

    assert_response :created
    assert_equal "in_progress", @task.reload.status
  end

  test "omitting task_id does not modify tasks" do
    post "/v1/agent/objectives/#{@objective.id}/research_snapshots",
         params: { research_snapshot: { key: "30yr_rate", value: "6.85%" } },
         as: :json, headers: agent_headers

    assert_response :created
    assert_equal "in_progress", @task.reload.status
  end

  test "rejects raw tool-call JSON as snapshot value" do
    junk = '{"tool_calls":[{"name":"multi_step_search","arguments":{"steps_json":"[]"}}]}'

    post "/v1/agent/objectives/#{@objective.id}/research_snapshots",
         params: { research_snapshot: { key: "bad", value: junk } },
         as: :json, headers: agent_headers

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_match(/plain-language|JSON|structured/i, body["error"].to_s)
  end

  test "rejects non-tool JSON object values" do
    post "/v1/agent/objectives/#{@objective.id}/research_snapshots",
         params: { research_snapshot: { key: "structured_note", value: '{"hotel":"Grand","nightly":189}' } },
         as: :json, headers: agent_headers

    assert_response :unprocessable_entity
  end

  test "index lists research snapshots for objective" do
    @objective.research_snapshots.create!(
      key: "rate", value: "6.5%", checked_at: Time.current, task_id: @task.id
    )

    get "/v1/agent/objectives/#{@objective.id}/research_snapshots",
        as: :json, headers: agent_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["research_snapshots"].length
    assert_equal "rate", body["research_snapshots"].first["key"]
    assert_equal "6.5%", body["research_snapshots"].first["value"]
  end

  test "index with task_id includes nil task_id snapshots and matching task" do
    @objective.research_snapshots.create!(key: "shared", value: "note", checked_at: Time.current, task_id: nil)
    other_task = @objective.tasks.create!(description: "Other", status: "pending")
    @objective.research_snapshots.create!(key: "other", value: "x", checked_at: Time.current, task_id: other_task.id)
    @objective.research_snapshots.create!(key: "mine", value: "for this task", checked_at: Time.current, task_id: @task.id)

    get "/v1/agent/objectives/#{@objective.id}/research_snapshots",
        params: { task_id: @task.id },
        as: :json, headers: agent_headers

    assert_response :success
    body = JSON.parse(response.body)
    keys = body["research_snapshots"].map { |s| s["key"] }.sort
    assert_equal %w[mine shared], keys
  end

  # ── auth / isolation ────────────────────────────────────────────────────────

  test "requires valid bearer token" do
    post "/v1/agent/objectives/#{@objective.id}/research_snapshots",
         params: { research_snapshot: { key: "k", value: "v" } },
         as: :json, headers: workspace_headers   # no Authorization header

    assert_response :unauthorized
  end

  test "returns 404 for objective belonging to another workspace" do
    other     = Workspace.create!(name: "Other", slug: "other-#{SecureRandom.hex(4)}")
    other_obj = other.objectives.create!(goal: "Private goal", status: "pending")

    post "/v1/agent/objectives/#{other_obj.id}/research_snapshots",
         params: { research_snapshot: { key: "k", value: "v" } },
         as: :json, headers: agent_headers

    assert_response :not_found
  end

  private

  def workspace_headers
    { "X-Workspace-Slug" => @workspace.slug, "ACCEPT" => "application/json" }
  end

  def agent_headers
    workspace_headers.merge("Authorization" => "Bearer test-agent-token")
  end
end
