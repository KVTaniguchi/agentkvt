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

  test "index serializes guided objective metadata when present" do
    objective = @workspace.objectives.create!(
      goal: "Plan a date night",
      status: "pending",
      priority: 0,
      objective_kind: "date_night",
      creation_source: "guided",
      brief_json: {
        context: ["Friday night in Brooklyn"],
        success_criteria: ["Dinner and one activity"],
        constraints: ["Stay under $180"],
        preferences: ["Cozy atmosphere"],
        deliverable: "Recommended plan with backup option",
        open_questions: []
      }
    )

    get "/v1/objectives", headers: workspace_headers
    assert_response :success

    serialized = JSON.parse(response.body)["objectives"].find { |item| item["id"] == objective.id.to_s }
    assert_equal "date_night", serialized["objective_kind"]
    assert_equal "guided", serialized["creation_source"]
    assert_equal [ "Friday night in Brooklyn" ], serialized.dig("brief_json", "context")
    assert_includes serialized["planner_summary"], "Objective archetype: Date Night"
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

  test "create accepts structured objective brief metadata" do
    with_stubbed_planner do
      post "/v1/objectives",
           params: {
             objective: {
               goal: "Create a monthly family budget",
               status: "pending",
               objective_kind: "budget",
               creation_source: "manual",
               brief_json: {
                 context: ["Monthly family budget"],
                 success_criteria: ["Save $500 per month"],
                 constraints: ["Keep dining out under $300"],
                 preferences: ["Simple categories"],
                 deliverable: "Monthly category budget",
                 open_questions: []
               }
             }
           },
           as: :json,
           headers: workspace_headers
    end

    assert_response :created
    created = @workspace.objectives.order(:created_at).last
    assert_equal "budget", created.objective_kind
    assert_equal "manual", created.creation_source
    assert_equal [ "Monthly family budget" ], created.brief_json["context"]
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
    feedback = objective.objective_feedbacks.create!(
      content: "Look for refundable options next.",
      feedback_kind: "follow_up",
      status: "queued"
    )
    @workspace.agent_logs.create!(
      phase: "worker_claim",
      content: "Claimed a flight-research work unit",
      metadata_json: {
        "mission_name" => "Objective Worker alpha",
        "objective_id" => objective.id.to_s,
        "worker_label" => "objective-worker-1"
      }
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
    assert_equal 1,                 body["objective_feedbacks"].length
    assert_equal feedback.id.to_s,  body["objective_feedbacks"].first["id"]
    assert_equal "Look for refundable options next.", body["objective_feedbacks"].first["content"]
    assert_equal 1,                 body["agent_logs"].length
    assert_equal "Objective Worker alpha", body["agent_logs"].first.dig("metadata_json", "mission_name")
    assert_equal 0,                 body["online_agent_registrations_count"]
  end

  test "show includes viewer-specific snapshot feedback fields and aggregate counts" do
    objective = @workspace.objectives.create!(goal: "Book flights", status: "active", priority: 2)
    snapshot = objective.research_snapshots.create!(
      key: "cheapest_fare", value: "$299", checked_at: Time.current
    )
    member = @workspace.family_members.create!(display_name: "Kevin", symbol: "K", source: "ios")
    objective.research_snapshot_feedbacks.create!(
      workspace: @workspace,
      research_snapshot: snapshot,
      created_by_profile: member,
      role: "user",
      rating: "bad",
      reason: "Stale price"
    )

    get "/v1/objectives/#{objective.id}", params: { viewer_profile_id: member.id }, headers: workspace_headers
    assert_response :success

    serialized = JSON.parse(response.body).fetch("research_snapshots").first
    assert_equal "bad", serialized["viewer_feedback_rating"]
    assert_equal "Stale price", serialized["viewer_feedback_reason"]
    assert_equal 0, serialized["good_feedback_count"]
    assert_equal 1, serialized["bad_feedback_count"]
  end

  test "create and update research snapshot feedback" do
    objective = @workspace.objectives.create!(goal: "Book flights", status: "active", priority: 2)
    snapshot = objective.research_snapshots.create!(
      key: "cheapest_fare", value: "$299", checked_at: Time.current
    )
    member = @workspace.family_members.create!(display_name: "Kevin", symbol: "K", source: "ios")

    post "/v1/objectives/#{objective.id}/research_snapshots/#{snapshot.id}/feedback",
         params: {
           research_snapshot_feedback: {
             created_by_profile_id: member.id,
             rating: "bad",
             reason: "Outdated"
           }
         },
         as: :json,
         headers: workspace_headers
    assert_response :created

    feedback_id = JSON.parse(response.body).dig("research_snapshot_feedback", "id")
    assert_equal 1, objective.reload.research_snapshot_feedbacks.count

    patch "/v1/objectives/#{objective.id}/research_snapshots/#{snapshot.id}/feedback/#{feedback_id}",
          params: {
            research_snapshot_feedback: {
              rating: "good",
              reason: "Looks verified now"
            }
          },
          as: :json,
          headers: workspace_headers
    assert_response :success

    feedback = objective.reload.research_snapshot_feedbacks.first
    assert_equal "good", feedback.rating
    assert_equal "Looks verified now", feedback.reason
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

  test "update from pending to active re-enqueues pending tasks when they already exist" do
    objective = @workspace.objectives.create!(goal: "Already has work", status: "pending", priority: 0)
    task = objective.tasks.create!(description: "Existing task", status: "pending")
    enqueued_task_ids = []

    with_stubbed_task_executor do |stub|
      stub.define_singleton_method(:perform_later) do |task_id|
        enqueued_task_ids << task_id
      end

      patch "/v1/objectives/#{objective.id}",
            params: { objective: { goal: "Already has work", status: "active", priority: 0 } },
            as: :json, headers: workspace_headers
    end

    assert_response :success
    assert_equal [task.id.to_s], enqueued_task_ids
  end

  test "run_now activates a pending objective and invokes ObjectivePlanner" do
    planner_called = false
    objective = @workspace.objectives.create!(goal: "Need kickoff", status: "pending", priority: 0)

    with_stubbed_planner do |stub|
      stub.define_singleton_method(:call) do |obj|
        planner_called = true
        []
      end

      post "/v1/objectives/#{objective.id}/run_now", headers: workspace_headers
    end

    assert_response :success
    assert planner_called
    assert_equal "active", objective.reload.status
  end

  test "run_now retries planning for an active objective with no tasks" do
    planner_call_count = 0
    objective = @workspace.objectives.create!(goal: "Retry me", status: "active", priority: 0)

    with_stubbed_planner do |stub|
      stub.define_singleton_method(:call) do |obj|
        planner_call_count += 1
        []
      end

      post "/v1/objectives/#{objective.id}/run_now", headers: workspace_headers
    end

    assert_response :success
    assert_equal 1, planner_call_count
  end

  test "run_now re-enqueues pending tasks without invoking ObjectivePlanner" do
    objective = @workspace.objectives.create!(goal: "Kick queued task", status: "active", priority: 0)
    task = objective.tasks.create!(description: "Queued task", status: "pending")
    planner_called = false
    enqueued_task_ids = []

    with_stubbed_planner do |planner_stub|
      planner_stub.define_singleton_method(:call) do |_obj|
        planner_called = true
        []
      end

      with_stubbed_task_executor do |job_stub|
        job_stub.define_singleton_method(:perform_later) do |task_id|
          enqueued_task_ids << task_id
        end

        post "/v1/objectives/#{objective.id}/run_now", headers: workspace_headers
      end
    end

    assert_response :success
    assert_equal false, planner_called
    assert_equal [task.id.to_s], enqueued_task_ids
  end

  test "run_now retries failed tasks by resetting them to pending and enqueueing them" do
    objective = @workspace.objectives.create!(goal: "Retry failed task", status: "active", priority: 0)
    task = objective.tasks.create!(description: "Recover task", status: "failed", result_summary: "Old failure")
    enqueued_task_ids = []

    with_stubbed_task_executor do |job_stub|
      job_stub.define_singleton_method(:perform_later) do |task_id|
        enqueued_task_ids << task_id
      end

      post "/v1/objectives/#{objective.id}/run_now", headers: workspace_headers
    end

    assert_response :success
    assert_equal "pending", task.reload.status
    assert_nil task.result_summary
    assert_equal [task.id.to_s], enqueued_task_ids
  end

  test "run_now rejects objectives whose plan still needs review" do
    objective = @workspace.objectives.create!(goal: "Review me first", status: "active", priority: 0)
    objective.tasks.create!(description: "Proposed task", status: "proposed")

    post "/v1/objectives/#{objective.id}/run_now", headers: workspace_headers

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body).fetch("error"), "approve"
  end

  test "approve_plan converts proposed tasks to pending and enqueues them for active objectives" do
    objective = @workspace.objectives.create!(goal: "Trip plan", status: "active", priority: 0)
    a = objective.tasks.create!(description: "Compare flights", status: "proposed")
    b = objective.tasks.create!(description: "Compare hotels", status: "proposed")
    enqueued = []

    with_stubbed_task_executor do |job_stub|
      job_stub.define_singleton_method(:perform_later) do |task_id|
        enqueued << task_id
      end

      post "/v1/objectives/#{objective.id}/approve_plan", headers: workspace_headers
    end

    assert_response :success
    assert_equal "pending", a.reload.status
    assert_equal "pending", b.reload.status
    assert_equal [a.id.to_s, b.id.to_s].sort, enqueued.sort
  end

  test "approve_plan leaves pending objectives unqueued after approval" do
    objective = @workspace.objectives.create!(goal: "Plan later", status: "pending", priority: 0)
    task = objective.tasks.create!(description: "Draft task", status: "proposed")
    enqueued = []

    with_stubbed_task_executor do |job_stub|
      job_stub.define_singleton_method(:perform_later) do |task_id|
        enqueued << task_id
      end

      post "/v1/objectives/#{objective.id}/approve_plan", headers: workspace_headers
    end

    assert_response :success
    assert_equal "pending", task.reload.status
    assert_equal [], enqueued
  end

  test "feedback creates a review-required follow-up batch when multiple next steps are needed" do
    objective = @workspace.objectives.create!(goal: "Plan a family beach trip", status: "active", priority: 0)
    completed_task = objective.tasks.create!(description: "Compare hotel options", status: "completed", result_summary: "Loews and Hotel del Coronado")
    snapshot = objective.research_snapshots.create!(
      key: "hotel_shortlist",
      value: "Loews and Hotel del Coronado are the strongest options so far",
      task: completed_task,
      checked_at: Time.current
    )
    enqueued = []

    with_stubbed_feedback_planner do |planner_stub|
      planner_stub.define_singleton_method(:call) do |feedback|
        [
          feedback.objective.tasks.create!(
            description: "Compare resort fees for the shortlisted hotels",
            status: "proposed",
            source_feedback: feedback
          ),
          feedback.objective.tasks.create!(
            description: "Compare walking distance to the beach and pool setup",
            status: "proposed",
            source_feedback: feedback
          )
        ]
      end

      with_stubbed_task_executor do |job_stub|
        job_stub.define_singleton_method(:perform_later) { |task_id| enqueued << task_id }

        post "/v1/objectives/#{objective.id}/feedback",
             params: {
               objective_feedback: {
                 content: "Go deeper on resort fees and beach access.",
                 feedback_kind: "compare_options",
                 task_id: completed_task.id,
                 research_snapshot_id: snapshot.id
               }
             },
             as: :json,
             headers: workspace_headers
      end
    end

    assert_response :created
    feedback = objective.reload.objective_feedbacks.last
    assert_equal "review_required", feedback.status
    assert_equal "compare_options", feedback.feedback_kind
    assert_equal completed_task.id, feedback.task_id
    assert_equal snapshot.id, feedback.research_snapshot_id
    created_tasks = objective.tasks.where(source_feedback: feedback).order(:created_at)
    assert_equal 2, created_tasks.count
    assert_equal %w[proposed proposed], created_tasks.map(&:status)
    assert_equal [], enqueued
  end

  test "feedback creates one queued follow-up task and enqueues it for active objectives" do
    objective = @workspace.objectives.create!(goal: "Plan a family beach trip", status: "active", priority: 0)
    enqueued = []

    with_stubbed_feedback_planner do |planner_stub|
      planner_stub.define_singleton_method(:call) do |feedback|
        [
          feedback.objective.tasks.create!(
            description: "Verify whether the top hotel options include free parking",
            status: "pending",
            source_feedback: feedback
          )
        ]
      end

      with_stubbed_task_executor do |job_stub|
        job_stub.define_singleton_method(:perform_later) { |task_id| enqueued << task_id }

        post "/v1/objectives/#{objective.id}/feedback",
             params: {
               objective_feedback: {
                 content: "Check whether parking is free at the best hotel options.",
                 feedback_kind: "clarify_gaps"
               }
             },
             as: :json,
             headers: workspace_headers
      end
    end

    assert_response :created
    feedback = objective.reload.objective_feedbacks.last
    assert_equal "queued", feedback.status
    created_tasks = objective.tasks.where(source_feedback: feedback).order(:created_at)
    assert_equal 1, created_tasks.count
    assert_equal [ "pending" ], created_tasks.map(&:status)
    assert_equal created_tasks.map { |task| task.id.to_s }, enqueued
  end

  test "feedback creates pending follow-up tasks for pending objectives" do
    objective = @workspace.objectives.create!(goal: "Research birthday venues", status: "pending", priority: 0)
    enqueued = []

    with_stubbed_feedback_planner do |planner_stub|
      planner_stub.define_singleton_method(:call) do |feedback|
        [
          feedback.objective.tasks.create!(
            description: "Compare the best venue options by hourly cost and food flexibility",
            status: "pending",
            source_feedback: feedback
          )
        ]
      end

      with_stubbed_task_executor do |job_stub|
        job_stub.define_singleton_method(:perform_later) { |task_id| enqueued << task_id }

        post "/v1/objectives/#{objective.id}/feedback",
             params: {
               objective_feedback: {
                 content: "Compare the strongest options by hourly cost and whether we can bring our own cake.",
                 feedback_kind: "clarify_gaps"
               }
             },
             as: :json,
             headers: workspace_headers
      end
    end

    assert_response :created
    feedback = objective.reload.objective_feedbacks.last
    assert_equal "planned", feedback.status
    assert_equal 1, objective.tasks.where(source_feedback: feedback, status: "pending").count
    assert_equal [], enqueued
  end

  test "approve feedback plan converts proposed follow-up tasks to pending and enqueues them for active objectives" do
    objective = @workspace.objectives.create!(goal: "Plan a beach trip", status: "active", priority: 0)
    feedback = objective.objective_feedbacks.create!(
      content: "Compare the top hotel options in more detail.",
      feedback_kind: "compare_options",
      status: "review_required"
    )
    a = objective.tasks.create!(description: "Compare resort fees", status: "proposed", source_feedback: feedback)
    b = objective.tasks.create!(description: "Compare beach access", status: "proposed", source_feedback: feedback)
    enqueued = []

    with_stubbed_task_executor do |job_stub|
      job_stub.define_singleton_method(:perform_later) { |task_id| enqueued << task_id }

      post "/v1/objectives/#{objective.id}/objective_feedbacks/#{feedback.id}/approve_plan", headers: workspace_headers
    end

    assert_response :success
    assert_equal "queued", feedback.reload.status
    assert_equal %w[pending pending], [a.reload.status, b.reload.status]
    assert_equal [a.id.to_s, b.id.to_s].sort, enqueued.sort
  end

  test "regenerate feedback plan replaces only the proposed follow-up tasks" do
    objective = @workspace.objectives.create!(goal: "Plan a beach trip", status: "active", priority: 0)
    feedback = objective.objective_feedbacks.create!(
      content: "Compare the top hotel options in more detail.",
      feedback_kind: "compare_options",
      status: "review_required"
    )
    stale = objective.tasks.create!(description: "Old follow-up", status: "proposed", source_feedback: feedback)
    untouched = objective.tasks.create!(description: "Existing base task", status: "completed")

    with_stubbed_feedback_planner do |planner_stub|
      planner_stub.define_singleton_method(:call) do |current_feedback|
        [
          current_feedback.objective.tasks.create!(
            description: "Compare resort fees for the best two hotels",
            status: "proposed",
            source_feedback: current_feedback
          ),
          current_feedback.objective.tasks.create!(
            description: "Compare beach setup for each hotel",
            status: "proposed",
            source_feedback: current_feedback
          )
        ]
      end

      post "/v1/objectives/#{objective.id}/objective_feedbacks/#{feedback.id}/regenerate_plan", headers: workspace_headers
    end

    assert_response :success
    assert_not Task.exists?(stale.id)
    assert Task.exists?(untouched.id)
    assert_equal 2, objective.reload.tasks.where(source_feedback: feedback).count
    assert_equal "review_required", feedback.reload.status
  end

  test "update feedback plan edits the feedback and replans before dispatch" do
    objective = @workspace.objectives.create!(goal: "Plan a beach trip", status: "active", priority: 0)
    completed_task = objective.tasks.create!(description: "Compare hotel options", status: "completed")
    feedback = objective.objective_feedbacks.create!(
      content: "Compare these hotels by beach access.",
      feedback_kind: "compare_options",
      status: "review_required",
      task: completed_task
    )
    objective.tasks.create!(description: "Old follow-up", status: "proposed", source_feedback: feedback)

    with_stubbed_feedback_planner do |planner_stub|
      planner_stub.define_singleton_method(:call) do |current_feedback|
        [
          current_feedback.objective.tasks.create!(
            description: "Challenge the earlier beach access assumptions for each hotel",
            status: "pending",
            source_feedback: current_feedback
          )
        ]
      end

      patch "/v1/objectives/#{objective.id}/objective_feedbacks/#{feedback.id}",
            params: {
              objective_feedback: {
                content: "Challenge the earlier beach access assumptions.",
                feedback_kind: "challenge_result",
                task_id: completed_task.id
              }
            },
            as: :json,
            headers: workspace_headers
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "challenge_result", feedback.reload.feedback_kind
    assert_equal "Challenge the earlier beach access assumptions.", feedback.content
    assert_equal 1, body.fetch("follow_up_tasks").length
    assert_equal "queued", feedback.reload.status
  end

  test "completed follow-up tasks produce a what-changed summary on the feedback" do
    objective = @workspace.objectives.create!(goal: "Plan a beach trip", status: "active", priority: 0)
    feedback = objective.objective_feedbacks.create!(
      content: "Verify whether the top hotel has direct beach access.",
      feedback_kind: "clarify_gaps",
      status: "queued"
    )
    task = objective.tasks.create!(
      description: "Verify whether the top hotel has direct beach access",
      status: "pending",
      source_feedback: feedback
    )

    post "/v1/agent/objectives/#{objective.id}/research_snapshots",
         params: {
           task_id: task.id,
           mark_task_completed: true,
           research_snapshot: {
             key: "beach_access",
             value: "Hotel del Coronado has direct beach access from the property."
           }
         },
         as: :json,
         headers: workspace_headers

    assert_response :created
    assert_equal "completed", feedback.reload.status
    assert feedback.completed_at.present?
    assert_includes feedback.completion_summary, "What changed"
  end

  test "feedback rejects anchors that belong to a different objective" do
    objective = @workspace.objectives.create!(goal: "Track mortgage rates", status: "active", priority: 0)
    other_objective = @workspace.objectives.create!(goal: "Track gas prices", status: "active", priority: 0)
    other_task = other_objective.tasks.create!(description: "Compare nearby gas stations", status: "completed")

    post "/v1/objectives/#{objective.id}/feedback",
         params: {
           objective_feedback: {
             content: "Dig deeper here.",
             task_id: other_task.id
           }
         },
         as: :json,
         headers: workspace_headers

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body).fetch("error"), "same objective"
  end

  test "regenerate_plan clears proposed tasks and re-enqueues planning" do
    objective = @workspace.objectives.create!(goal: "Redo the plan", status: "active", priority: 0)
    task = objective.tasks.create!(description: "Old proposed task", status: "proposed")
    objective.research_snapshots.create!(key: "draft", value: "stale", checked_at: Time.current)
    enqueued_ids = []

    with_stubbed_objective_planner_job do |stub|
      stub.define_singleton_method(:perform_later) { |id| enqueued_ids << id }
      post "/v1/objectives/#{objective.id}/regenerate_plan", headers: workspace_headers
    end

    assert_response :accepted
    assert_not Task.exists?(task.id)
    assert_equal 0, objective.reload.research_snapshots.count
    assert_equal [objective.id.to_s], enqueued_ids
  end

  test "regenerate_plan rejects objectives after execution has begun" do
    objective = @workspace.objectives.create!(goal: "Too late", status: "active", priority: 0)
    objective.tasks.create!(description: "Started task", status: "completed")

    post "/v1/objectives/#{objective.id}/regenerate_plan", headers: workspace_headers

    assert_response :unprocessable_entity
  end

  test "reset_stuck_tasks_and_run moves in_progress tasks to pending and enqueue" do
    objective = @workspace.objectives.create!(goal: "Stuck", status: "active", priority: 0)
    stuck = objective.tasks.create!(description: "Stuck", status: "in_progress", result_summary: "half")
    enqueued = []

    with_stubbed_task_executor do |job_stub|
      job_stub.define_singleton_method(:perform_later) do |task_id|
        enqueued << task_id
      end

      post "/v1/objectives/#{objective.id}/reset_stuck_tasks_and_run", headers: workspace_headers
    end

    assert_response :success
    assert_equal "pending", stuck.reload.status
    assert_nil stuck.result_summary
    assert_equal [stuck.id.to_s], enqueued
  end

  test "rerun resets all tasks to pending and enqueue" do
    objective = @workspace.objectives.create!(goal: "Redo", status: "active", priority: 0)
    a = objective.tasks.create!(description: "A", status: "completed", result_summary: "done")
    b = objective.tasks.create!(description: "B", status: "in_progress", result_summary: "busy")
    enqueued = []

    with_stubbed_task_executor do |job_stub|
      job_stub.define_singleton_method(:perform_later) do |task_id|
        enqueued << task_id
      end

      post "/v1/objectives/#{objective.id}/rerun", headers: workspace_headers
    end

    assert_response :success
    assert_equal "pending", a.reload.status
    assert_nil a.result_summary
    assert_equal "pending", b.reload.status
    assert_nil b.result_summary
    assert_equal [a.id.to_s, b.id.to_s].sort, enqueued.sort
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

  # ── presentation ─────────────────────────────────────────────────────────

  test "presentation returns ready status with cached layout when fresh" do
    objective = @workspace.objectives.create!(goal: "Trip plan", status: "active", priority: 0)
    layout = { "layout" => { "type" => "vstack", "children" => [] } }.to_json
    objective.update_columns(
      presentation_json: layout,
      presentation_generated_at: Time.current
    )

    get "/v1/objectives/#{objective.id}/presentation", headers: workspace_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "ready", body["status"]
    assert_not_nil body["layout"]
  end

  test "presentation enqueues job and returns generating when no presentation exists" do
    objective = @workspace.objectives.create!(goal: "New objective", status: "active", priority: 0)
    enqueued_ids = []

    with_stubbed_presentation_job do |stub|
      stub.define_singleton_method(:perform_later) { |id| enqueued_ids << id }
      get "/v1/objectives/#{objective.id}/presentation", headers: workspace_headers
    end

    assert_response :accepted
    assert_equal "generating", JSON.parse(response.body)["status"]
    assert_equal [ objective.id.to_s ], enqueued_ids
    assert_not_nil objective.reload.presentation_enqueued_at
  end

  test "presentation does not enqueue a second job when one was recently enqueued" do
    objective = @workspace.objectives.create!(goal: "Already queued", status: "active", priority: 0)
    objective.update_column(:presentation_enqueued_at, 30.seconds.ago)
    enqueued_ids = []

    with_stubbed_presentation_job do |stub|
      stub.define_singleton_method(:perform_later) { |id| enqueued_ids << id }
      get "/v1/objectives/#{objective.id}/presentation", headers: workspace_headers
    end

    assert_response :accepted
    assert_equal "generating", JSON.parse(response.body)["status"]
    assert_empty enqueued_ids
  end

  test "presentation re-enqueues after debounce window expires" do
    objective = @workspace.objectives.create!(goal: "Expired debounce", status: "active", priority: 0)
    objective.update_column(:presentation_enqueued_at, 91.seconds.ago)
    enqueued_ids = []

    with_stubbed_presentation_job do |stub|
      stub.define_singleton_method(:perform_later) { |id| enqueued_ids << id }
      get "/v1/objectives/#{objective.id}/presentation", headers: workspace_headers
    end

    assert_response :accepted
    assert_equal [ objective.id.to_s ], enqueued_ids
  end

  test "presentation returns generating when cached presentation is stale" do
    objective = @workspace.objectives.create!(goal: "Stale result", status: "active", priority: 0)
    task = objective.tasks.create!(description: "Research it", status: "completed")
    old_layout = { "layout" => { "type" => "vstack", "children" => [] } }.to_json
    objective.update_columns(presentation_json: old_layout, presentation_generated_at: 10.minutes.ago)
    objective.research_snapshots.create!(key: "price", value: "$5", task: task, checked_at: Time.current)
    enqueued_ids = []

    with_stubbed_presentation_job do |stub|
      stub.define_singleton_method(:perform_later) { |id| enqueued_ids << id }
      get "/v1/objectives/#{objective.id}/presentation", headers: workspace_headers
    end

    assert_response :accepted
    assert_equal "generating", JSON.parse(response.body)["status"]
    assert_equal [ objective.id.to_s ], enqueued_ids
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
    original_planner = ObjectivePlanner.method(:new)
    original_job     = ObjectivePlannerJob.method(:perform_later)
    ObjectivePlanner.define_singleton_method(:new) { |**_kw| stub }
    # Controller now enqueues ObjectivePlannerJob instead of calling the planner inline;
    # run the stub synchronously so existing assertions still hold.
    ObjectivePlannerJob.define_singleton_method(:perform_later) do |obj_id|
      obj = Objective.find(obj_id)
      stub.call(obj)
    end
    yield stub
  ensure
    ObjectivePlanner.define_singleton_method(:new, &original_planner)
    ObjectivePlannerJob.define_singleton_method(:perform_later, &original_job)
  end

  def with_stubbed_task_executor
    stub = Object.new
    stub.define_singleton_method(:perform_later) { |_task_id| }
    original = TaskExecutorJob.method(:perform_later)
    TaskExecutorJob.define_singleton_method(:perform_later) { |task_id| stub.perform_later(task_id) }
    yield stub
  ensure
    TaskExecutorJob.define_singleton_method(:perform_later, &original)
  end

  def with_stubbed_presentation_job
    stub = Object.new
    stub.define_singleton_method(:perform_later) { |_id| }
    original = ObjectivePresentationJob.method(:perform_later)
    ObjectivePresentationJob.define_singleton_method(:perform_later) { |id| stub.perform_later(id) }
    yield stub
  ensure
    ObjectivePresentationJob.define_singleton_method(:perform_later, &original)
  end

  def with_stubbed_objective_planner_job
    stub = Object.new
    stub.define_singleton_method(:perform_later) { |_id| }
    original = ObjectivePlannerJob.method(:perform_later)
    ObjectivePlannerJob.define_singleton_method(:perform_later) { |id| stub.perform_later(id) }
    yield stub
  ensure
    ObjectivePlannerJob.define_singleton_method(:perform_later, &original)
  end

  def with_stubbed_feedback_planner
    stub = Object.new
    stub.define_singleton_method(:call) { |_feedback| [] }
    original = ObjectiveFeedbackPlanner.method(:new)
    ObjectiveFeedbackPlanner.define_singleton_method(:new) { |**_kw| stub }
    yield stub
  ensure
    ObjectiveFeedbackPlanner.define_singleton_method(:new, &original)
  end
end
