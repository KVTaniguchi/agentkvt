require "test_helper"
require "securerandom"

class V1ObjectiveDraftsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = Workspace.create!(name: "Test Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
  end

  test "create returns a draft snapshot with assistant turn and no objective kickoff" do
    with_stubbed_composer_turn do
      post "/v1/objective_drafts",
           params: { objective_draft: { template_key: "budget", seed_text: "Help me make a budget." } },
           as: :json,
           headers: workspace_headers
    end

    assert_response :created
    body = JSON.parse(response.body)
    draft = body.fetch("objective_draft")

    assert_equal "budget", draft["template_key"]
    assert_equal 2, draft["messages"].length
    assert_equal "user", draft["messages"].first["role"]
    assert_equal "assistant", draft["messages"].last["role"]
    assert_equal 0, @workspace.objectives.count
  end

  test "show resumes an existing draft" do
    draft = create_draft_with_assistant

    get "/v1/objective_drafts/#{draft.id}", headers: workspace_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal draft.id.to_s, body.dig("objective_draft", "id")
    assert_equal draft.objective_draft_messages.count, body.dig("objective_draft", "messages").count
  end

  test "show does not expose another workspace draft" do
    other = Workspace.create!(name: "Other", slug: "other-#{SecureRandom.hex(4)}")
    draft = other.objective_drafts.create!(template_key: "generic")

    get "/v1/objective_drafts/#{draft.id}", headers: workspace_headers

    assert_response :not_found
  end

  test "message create appends user and assistant turns without creating objectives" do
    draft = create_draft_with_assistant
    initial_message_count = draft.objective_draft_messages.count

    with_stubbed_composer_turn(
      assistant_message: "What budget cap should I target?",
      suggested_goal: "Build a realistic monthly budget.",
      brief_json: {
        "context" => ["Monthly budget"],
        "success_criteria" => [],
        "constraints" => [],
        "preferences" => [],
        "deliverable" => "",
        "open_questions" => []
      },
      missing_fields: ["constraints", "success_criteria", "deliverable"],
      ready_to_finalize: false
    ) do
      post "/v1/objective_drafts/#{draft.id}/messages",
           params: { objective_draft_message: { content: "We need to save at least $500 a month." } },
           as: :json,
           headers: workspace_headers
    end

    assert_response :created
    assert_equal 0, @workspace.objectives.count
    assert_equal initial_message_count + 2, draft.reload.objective_draft_messages.count
    assert_equal "assistant", draft.objective_draft_messages.chronological.last.role
  end

  test "finalize to pending creates an objective but does not enqueue planning" do
    draft = create_draft_with_assistant(ready_to_finalize: true)
    enqueued_ids = []

    with_replaced_class_method(ObjectivePlannerJob, :perform_later, ->(objective_id) { enqueued_ids << objective_id }) do
      post "/v1/objective_drafts/#{draft.id}/finalize",
           params: {
             objective_draft: {
               goal: "Create a monthly family budget with category limits",
               status: "pending",
               brief_json: {
                 context: ["Monthly family budget"],
                 success_criteria: ["Saves $500 per month"],
                 constraints: ["Keep dining out under $300"],
                 preferences: ["Simple category plan"],
                 deliverable: "Monthly budget by category",
                 open_questions: []
               }
             }
           },
           as: :json,
           headers: workspace_headers
    end

    assert_response :created
    created = @workspace.objectives.order(:created_at).last
    assert_equal "pending", created.status
    assert_equal "budget", created.objective_kind
    assert_equal "guided", created.creation_source
    assert_equal [], enqueued_ids
    assert_equal "finalized", draft.reload.status
  end

  test "finalize to active creates an objective and enqueues planning" do
    draft = create_draft_with_assistant(ready_to_finalize: true)
    enqueued_ids = []

    with_replaced_class_method(ObjectivePlannerJob, :perform_later, ->(objective_id) { enqueued_ids << objective_id }) do
      post "/v1/objective_drafts/#{draft.id}/finalize",
           params: {
             objective_draft: {
               goal: "Plan a Friday Brooklyn date night under budget",
               status: "active",
               brief_json: {
                 context: ["Friday Brooklyn date night for two"],
                 success_criteria: ["Dinner and one activity"],
                 constraints: ["Stay under $180"],
                 preferences: ["Cozy vibe"],
                 deliverable: "Recommended plan with backup option",
                 open_questions: []
               }
             }
           },
           as: :json,
           headers: workspace_headers
    end

    assert_response :created
    created = @workspace.objectives.order(:created_at).last
    assert_equal "active", created.status
    assert_equal [created.id.to_s], enqueued_ids
    assert_equal created.id, draft.reload.finalized_objective_id
  end

  test "create prunes stale unfinalized drafts older than seven days" do
    stale = @workspace.objective_drafts.create!(template_key: "generic")
    stale.objective_draft_messages.create!(role: "assistant", content: "Old draft")
    stale.update_columns(created_at: 8.days.ago, updated_at: 8.days.ago)

    with_stubbed_composer_turn do
      post "/v1/objective_drafts",
           params: { objective_draft: { template_key: "generic" } },
           as: :json,
           headers: workspace_headers
    end

    assert_response :created
    assert_not ObjectiveDraft.exists?(stale.id)
  end

  private

  def create_draft_with_assistant(ready_to_finalize: false)
    draft = @workspace.objective_drafts.create!(
      template_key: "budget",
      brief_json: {
        context: ["Need a monthly budget"],
        success_criteria: ready_to_finalize ? ["Saves $500 per month"] : [],
        constraints: ready_to_finalize ? ["Keep total discretionary spending under $900"] : [],
        preferences: ["Simple categories"],
        deliverable: ready_to_finalize ? "Monthly category budget" : "",
        open_questions: []
      },
      suggested_goal: "Create a monthly family budget.",
      assistant_message: ready_to_finalize ? "This is ready to review." : "What budget cap should I target?",
      missing_fields: ready_to_finalize ? [] : ["constraints", "success_criteria", "deliverable"],
      ready_to_finalize: ready_to_finalize
    )
    draft.objective_draft_messages.create!(role: "assistant", content: draft.assistant_message)
    draft
  end

  def with_stubbed_composer_turn(
    assistant_message: "What monthly savings target should I plan around?",
    suggested_goal: "Create a monthly family budget with clear category targets.",
    brief_json: {
      "context" => ["Monthly family budget"],
      "success_criteria" => [],
      "constraints" => [],
      "preferences" => [],
      "deliverable" => "",
      "open_questions" => []
    },
    missing_fields: ["constraints", "success_criteria", "deliverable"],
    ready_to_finalize: false
  )
    composer = Object.new
    composer.define_singleton_method(:call) do |_draft|
      {
        "assistant_message" => assistant_message,
        "suggested_goal" => suggested_goal,
        "brief_json" => brief_json,
        "missing_fields" => missing_fields,
        "ready_to_finalize" => ready_to_finalize
      }
    end

    with_replaced_class_method(ObjectiveComposer, :new, ->(*, **) { composer }) do
      yield
    end
  end

  def with_replaced_class_method(klass, method_name, callable)
    singleton = class << klass
      self
    end
    method_defined = singleton.method_defined?(method_name) || singleton.private_method_defined?(method_name)
    original_method = klass.method(method_name) if method_defined

    singleton.send(:define_method, method_name, &callable)
    yield
  ensure
    if method_defined && original_method
      singleton.send(:define_method, method_name, original_method)
    elsif singleton.method_defined?(method_name) || singleton.private_method_defined?(method_name)
      singleton.send(:remove_method, method_name)
    end
  end

  def workspace_headers
    { "X-Workspace-Slug" => @workspace.slug }
  end
end
