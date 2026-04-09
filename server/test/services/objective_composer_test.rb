require "test_helper"
require "securerandom"

class ObjectiveComposerTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Test Workspace", slug: "workspace-#{SecureRandom.hex(4)}")
  end

  test "budget draft normalizes incomplete response and keeps ready false" do
    draft = @workspace.objective_drafts.create!(template_key: "budget")
    draft.objective_draft_messages.create!(role: "user", content: "Help me make a monthly family budget.")

    response = {
      assistant_message: "What monthly savings target and hard limits should I plan around?",
      suggested_goal: "Create a monthly family budget with clear category limits.",
      brief_json: {
        context: ["Monthly family budget for our household"],
        constraints: ["Need to keep total spending under our take-home pay"],
        success_criteria: [],
        preferences: ["Simple categories and a realistic plan"],
        deliverable: "",
        open_questions: ["What monthly savings target should we use?"]
      },
      missing_fields: ["success_criteria", "deliverable"],
      ready_to_finalize: false
    }.to_json

    turn = ObjectiveComposer.new(client: stub_client(response)).call(draft)

    assert_equal false, turn["ready_to_finalize"]
    assert_equal "Create a monthly family budget with clear category limits.", turn["suggested_goal"]
    assert_includes turn["missing_fields"], "success_criteria"
    assert_includes turn["missing_fields"], "deliverable"
    assert_equal [ "Monthly family budget for our household" ], turn.dig("brief_json", "context")
  end

  test "date night draft can become ready when required fields are filled" do
    draft = @workspace.objective_drafts.create!(template_key: "date_night")
    draft.objective_draft_messages.create!(role: "user", content: "Help me plan a Friday date night in Brooklyn.")

    response = {
      assistant_message: "This is ready to review.",
      suggested_goal: "Plan a Friday night Brooklyn date with dinner and one activity under budget.",
      brief_json: {
        context: ["Friday date night in Brooklyn for two"],
        success_criteria: ["Includes dinner and one activity", "Feels relaxed and memorable"],
        constraints: ["Keep total spend under $180", "Need to be home by 10 PM"],
        preferences: ["Prefer cozy places over loud venues"],
        deliverable: "A short recommended plan with backup options",
        open_questions: []
      },
      missing_fields: [],
      ready_to_finalize: true
    }.to_json

    turn = ObjectiveComposer.new(client: stub_client(response)).call(draft)

    assert_equal true, turn["ready_to_finalize"]
    assert_equal [], turn["missing_fields"]
    assert_equal "Plan a Friday night Brooklyn date with dinner and one activity under budget.", turn["suggested_goal"]
  end

  test "trip planning draft falls back when ollama returns malformed json" do
    draft = @workspace.objective_drafts.create!(template_key: "trip_planning")
    draft.objective_draft_messages.create!(role: "user", content: "Plan a Tokyo trip for two in October with a mid-range budget.")

    turn = ObjectiveComposer.new(client: stub_client("not-json")).call(draft)

    assert_equal false, turn["ready_to_finalize"]
    assert_includes turn.dig("brief_json", "context"), "Plan a Tokyo trip for two in October with a mid-range budget."
    assert_match(/what should i know/i, turn["assistant_message"])
    assert turn["suggested_goal"].present?
  end

  test "required missing fields override an overconfident llm response" do
    draft = @workspace.objective_drafts.create!(template_key: "budget")
    draft.objective_draft_messages.create!(role: "user", content: "Budget help")

    response = {
      assistant_message: "Ready to go.",
      suggested_goal: "Build a budget.",
      brief_json: {
        context: ["Need a budget"],
        success_criteria: [],
        constraints: [],
        preferences: [],
        deliverable: "",
        open_questions: []
      },
      missing_fields: [],
      ready_to_finalize: true
    }.to_json

    turn = ObjectiveComposer.new(client: stub_client(response)).call(draft)

    assert_equal false, turn["ready_to_finalize"]
    assert_includes turn["missing_fields"], "constraints"
    assert_includes turn["missing_fields"], "success_criteria"
    assert_includes turn["missing_fields"], "deliverable"
  end

  private

  def stub_client(response)
    client = Object.new
    client.define_singleton_method(:chat) { |**_kwargs| response }
    client
  end
end
