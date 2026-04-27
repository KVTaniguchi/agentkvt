require "test_helper"
require "securerandom"

class ObjectiveFeedbackPlannerTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Test Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
    @objective = @workspace.objectives.create!(goal: "Plan a San Diego trip", status: "active")
    @task = @objective.tasks.create!(
      description: "Compare hotel options near the beach",
      status: "completed",
      result_summary: "Top options were Hotel del Coronado and Loews Coronado Bay"
    )
    @snapshot = @objective.research_snapshots.create!(
      key: "hotel_shortlist",
      value: "Hotel del Coronado and Loews Coronado Bay are the top family-friendly options",
      task: @task,
      checked_at: Time.current
    )
  end

  test "creates up to 3 proposed follow-up tasks for active objectives when the batch needs review" do
    feedback = @objective.objective_feedbacks.create!(
      task: @task,
      research_snapshot: @snapshot,
      content: "Compare parking fees, resort fees, and walking distance to the beach.",
      feedback_kind: "compare_options",
      status: "received"
    )

    raw_json = JSON.generate([
      { "description" => "Compare parking fees across the top hotel options" },
      { "description" => "Compare resort fees and mandatory extras for each hotel" },
      { "description" => "Compare walking distance and beach access for each hotel" },
      { "description" => "This extra task should be dropped" }
    ])

    tasks = ObjectiveFeedbackPlanner.new(client: stub_client(raw_json)).call(feedback)

    assert_equal 3, tasks.length
    assert tasks.all? { |task| task.status == "proposed" }
    assert_equal [ feedback.id ], tasks.map(&:source_feedback_id).uniq
  end

  test "creates a pending follow-up task for an active objective when only one next step is needed" do
    feedback = @objective.objective_feedbacks.create!(
      content: "Verify whether resort fees apply to both finalists.",
      feedback_kind: "clarify_gaps",
      status: "received"
    )

    tasks = ObjectiveFeedbackPlanner.new(
      client: stub_client(JSON.generate([{ "description" => "Verify whether resort fees apply to both shortlisted hotels" }]))
    ).call(feedback)

    assert_equal 1, tasks.length
    assert_equal "pending", tasks.first.status
  end

  test "creates pending follow-up tasks for pending objectives when only one next step is needed" do
    objective = @workspace.objectives.create!(goal: "Research summer camps", status: "pending")
    feedback = objective.objective_feedbacks.create!(
      content: "Compare the best options by weekly price and extended-care availability.",
      feedback_kind: "compare_options",
      status: "received"
    )

    tasks = ObjectiveFeedbackPlanner.new(
      client: stub_client(JSON.generate([{ "description" => "Compare weekly price and extended-care availability for the best camp options" }]))
    ).call(feedback)

    assert_equal 1, tasks.length
    assert_equal "pending", tasks.first.status
    assert_equal feedback.id, tasks.first.source_feedback_id
  end

  test "final recommendation collapses multiple llm tasks into one pending synthesis step" do
    feedback = @objective.objective_feedbacks.create!(
      content: "Turn the findings into a recommendation with a backup option.",
      feedback_kind: "final_recommendation",
      status: "received"
    )

    raw_json = JSON.generate([
      { "description" => "Turn the current research into a concrete recommendation with a backup option" },
      { "description" => "Dig deeper into remaining price gaps before deciding" }
    ])

    tasks = ObjectiveFeedbackPlanner.new(client: stub_client(raw_json)).call(feedback)

    assert_equal 1, tasks.length
    assert_equal "pending", tasks.first.status
    assert_match(/recommendation/i, tasks.first.description)
  end

  test "planner prompt includes feedback anchor context and user feedback" do
    captured_messages = nil
    feedback = @objective.objective_feedbacks.create!(
      task: @task,
      research_snapshot: @snapshot,
      content: "Re-check whether Loews has hidden fees we missed.",
      feedback_kind: "challenge_result",
      status: "received"
    )

    client = Object.new
    client.define_singleton_method(:chat) do |messages:, **_kwargs|
      captured_messages = messages
      JSON.generate([{ "description" => "Validate whether Loews has additional hidden fees" }])
    end

    ObjectiveFeedbackPlanner.new(client: client).call(feedback)

    planning_input = captured_messages.last.fetch(:content)
    assert_includes planning_input, "Feedback intent: challenge result"
    assert_includes planning_input, "Re-check whether Loews has hidden fees we missed."
    assert_includes planning_input, @task.description
    assert_includes planning_input, @snapshot.key
  end

  test "planner prompt includes rated findings guidance" do
    member = @workspace.family_members.create!(display_name: "Kevin", symbol: "K", source: "ios")
    @objective.research_snapshot_feedbacks.create!(
      workspace: @workspace,
      research_snapshot: @snapshot,
      created_by_profile: member,
      role: "user",
      rating: "bad",
      reason: "Outdated and too vague"
    )

    captured_messages = nil
    feedback = @objective.objective_feedbacks.create!(
      content: "Keep going and tighten the recommendation.",
      feedback_kind: "follow_up",
      status: "received"
    )

    client = Object.new
    client.define_singleton_method(:chat) do |messages:, **_kwargs|
      captured_messages = messages
      JSON.generate([{ "description" => "Refresh the weak findings and compare the latest options" }])
    end

    ObjectiveFeedbackPlanner.new(client: client).call(feedback)

    planning_input = captured_messages.last.fetch(:content)
    assert_includes planning_input, "Negatively rated findings to avoid or re-check:"
    assert_includes planning_input, @snapshot.key
    assert_includes planning_input, "Outdated and too vague"
  end

  test "planner prompt includes brief anchors when objective has success criteria, constraints, and deliverable" do
    objective = @workspace.objectives.create!(
      goal: "Research electric bikes",
      status: "active",
      brief_json: {
        "success_criteria" => [ "Find a bike under $2,000", "Must have at least 40-mile range" ],
        "constraints" => [ "Available for purchase in the US", "Ships within 2 weeks" ],
        "deliverable" => "A ranked shortlist of 3 bikes with pros and cons"
      }
    )
    feedback = objective.objective_feedbacks.create!(
      content: "Compare the top brands on range and price.",
      feedback_kind: "compare_options",
      status: "received"
    )

    captured_messages = nil
    client = Object.new
    client.define_singleton_method(:chat) do |messages:, **_kwargs|
      captured_messages = messages
      JSON.generate([ { "description" => "Compare top electric bike brands on range and price" } ])
    end

    ObjectiveFeedbackPlanner.new(client: client).call(feedback)

    planning_input = captured_messages.last.fetch(:content)
    assert_includes planning_input, "ORIGINAL OBJECTIVE ANCHORS"
    assert_includes planning_input, "Success criterion: Find a bike under $2,000"
    assert_includes planning_input, "Constraint: Available for purchase in the US"
    assert_includes planning_input, "Deliverable: A ranked shortlist of 3 bikes with pros and cons"
  end

  test "planner prompt omits anchor section when brief_json is blank" do
    captured_messages = nil
    feedback = @objective.objective_feedbacks.create!(
      content: "Check availability for next weekend.",
      feedback_kind: "follow_up",
      status: "received"
    )

    client = Object.new
    client.define_singleton_method(:chat) do |messages:, **_kwargs|
      captured_messages = messages
      JSON.generate([ { "description" => "Check hotel availability for next weekend" } ])
    end

    ObjectiveFeedbackPlanner.new(client: client).call(feedback)

    planning_input = captured_messages.last.fetch(:content)
    refute_includes planning_input, "ORIGINAL OBJECTIVE ANCHORS"
  end

  test "inserts a proposed realignment task on every 3rd feedback cycle" do
    2.times do |i|
      @objective.objective_feedbacks.create!(
        content: "Prior feedback #{i + 1}",
        feedback_kind: "follow_up",
        status: "received"
      )
    end

    third_feedback = @objective.objective_feedbacks.create!(
      content: "Keep digging on the hotel options.",
      feedback_kind: "follow_up",
      status: "received"
    )

    tasks = ObjectiveFeedbackPlanner.new(
      client: stub_client(JSON.generate([ { "description" => "Dig deeper on hotel pricing" } ]))
    ).call(third_feedback)

    realignment_tasks = tasks.select { |t| t.task_kind == "synthesis" && t.status == "proposed" && t.description.include?("drifted") }
    assert_equal 1, realignment_tasks.length
    assert_equal third_feedback.id, realignment_tasks.first.source_feedback_id
  end

  test "does not insert a realignment task on non-cycle feedback" do
    feedback = @objective.objective_feedbacks.create!(
      content: "What is the cancellation policy?",
      feedback_kind: "clarify_gaps",
      status: "received"
    )

    tasks = ObjectiveFeedbackPlanner.new(
      client: stub_client(JSON.generate([ { "description" => "Look up cancellation policy" } ]))
    ).call(feedback)

    realignment_tasks = tasks.select { |t| t.description.include?("drifted") }
    assert_empty realignment_tasks
  end

  test "realignment task description embeds success criteria and constraints from brief_json" do
    objective = @workspace.objectives.create!(
      goal: "Plan a company offsite",
      status: "active",
      brief_json: {
        "success_criteria" => [ "All 20 attendees can attend", "Total cost under $15,000" ],
        "constraints" => [ "Must be within 2 hours of SF", "Must have AV equipment" ]
      }
    )
    2.times do |i|
      objective.objective_feedbacks.create!(
        content: "Prior feedback #{i + 1}",
        feedback_kind: "follow_up",
        status: "received"
      )
    end

    third_feedback = objective.objective_feedbacks.create!(
      content: "Any venue with outdoor space?",
      feedback_kind: "compare_options",
      status: "received"
    )

    ObjectiveFeedbackPlanner.new(
      client: stub_client(JSON.generate([ { "description" => "Find venues with outdoor space near SF" } ]))
    ).call(third_feedback)

    realignment_task = objective.tasks.find_by(task_kind: "synthesis", status: "proposed")
    assert_not_nil realignment_task
    assert_includes realignment_task.description, "All 20 attendees can attend"
    assert_includes realignment_task.description, "Must be within 2 hours of SF"
  end

  test "creates fallback follow-up tasks when the client raises" do
    feedback = @objective.objective_feedbacks.create!(
      content: "Turn the findings into a recommendation with a backup option.",
      feedback_kind: "final_recommendation",
      status: "received"
    )

    raising_client = Object.new
    raising_client.define_singleton_method(:chat) { |**_| raise "connection refused" }

    tasks = ObjectiveFeedbackPlanner.new(client: raising_client).call(feedback)

    assert_equal 1, tasks.length
    assert_equal "pending", tasks.first.status
    assert_equal feedback.id, tasks.first.source_feedback_id
  end

  private

  def stub_client(response)
    client = Object.new
    client.define_singleton_method(:chat) { |**_kwargs| response }
    client
  end
end
