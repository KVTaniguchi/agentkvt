require "test_helper"

class ObjectivePlanningInputBuilderTest < ActiveSupport::TestCase
  # --- call ---

  test "returns just the goal when no kind and no brief" do
    result = ObjectivePlanningInputBuilder.call(goal: "Find coffee shops")
    assert_equal "Find coffee shops", result
  end

  test "includes objective archetype when kind is present" do
    result = ObjectivePlanningInputBuilder.call(goal: "Plan a trip", objective_kind: "trip_planning")
    assert_match(/Goal: Plan a trip/, result)
    assert_match(/Objective archetype: Trip Planning/, result)
  end

  test "includes context section from brief" do
    brief = { "context" => ["Weekend trip", "Family of 4"] }
    result = ObjectivePlanningInputBuilder.call(goal: "Plan trip", brief_json: brief)
    assert_match(/Context:/, result)
    assert_match(/Weekend trip/, result)
    assert_match(/Family of 4/, result)
  end

  test "includes success_criteria section" do
    brief = { "success_criteria" => ["Find 3 options under $200"] }
    result = ObjectivePlanningInputBuilder.call(goal: "Plan trip", brief_json: brief)
    assert_match(/Success criteria:/, result)
    assert_match(/Find 3 options under \$200/, result)
  end

  test "includes constraints section" do
    brief = { "constraints" => ["No flying"] }
    result = ObjectivePlanningInputBuilder.call(goal: "Plan trip", brief_json: brief)
    assert_match(/Constraints:/, result)
    assert_match(/No flying/, result)
  end

  test "includes preferences section" do
    brief = { "preferences" => ["Vegan restaurants"] }
    result = ObjectivePlanningInputBuilder.call(goal: "Find dinner", brief_json: brief)
    assert_match(/Preferences:/, result)
    assert_match(/Vegan restaurants/, result)
  end

  test "includes deliverable section" do
    brief = { "deliverable" => "A ranked list of options" }
    result = ObjectivePlanningInputBuilder.call(goal: "Find options", brief_json: brief)
    assert_match(/Deliverable:/, result)
    assert_match(/A ranked list of options/, result)
  end

  test "includes open_questions section" do
    brief = { "open_questions" => ["Is parking included?"] }
    result = ObjectivePlanningInputBuilder.call(goal: "Find venue", brief_json: brief)
    assert_match(/Open questions:/, result)
    assert_match(/Is parking included\?/, result)
  end

  test "strips leading/trailing whitespace from goal" do
    result = ObjectivePlanningInputBuilder.call(goal: "  Find options  ")
    assert_equal "Find options", result
  end

  # --- normalize_brief ---

  test "returns blank hash fields when given nil" do
    brief = ObjectivePlanningInputBuilder.normalize_brief(nil)
    assert_equal [], brief["context"]
    assert_equal [], brief["success_criteria"]
    assert_nil brief["deliverable"]
  end

  test "normalizes brief from hash" do
    brief = ObjectivePlanningInputBuilder.normalize_brief({ "context" => ["Some context"] })
    assert_equal ["Some context"], brief["context"]
  end

  test "normalizes list entries by splitting on newlines" do
    brief = ObjectivePlanningInputBuilder.normalize_brief({ "context" => ["Line 1\nLine 2"] })
    assert_includes brief["context"], "Line 1"
    assert_includes brief["context"], "Line 2"
  end

  test "deduplicates list entries" do
    brief = ObjectivePlanningInputBuilder.normalize_brief({ "context" => ["Dup", "Dup"] })
    assert_equal ["Dup"], brief["context"]
  end

  test "strips blank strings from lists" do
    brief = ObjectivePlanningInputBuilder.normalize_brief({ "context" => ["  ", "Real entry"] })
    assert_not_includes brief["context"], ""
    assert_includes brief["context"], "Real entry"
  end

  # --- brief_present? ---

  test "returns false for empty brief" do
    assert_equal false, ObjectivePlanningInputBuilder.brief_present?(nil)
  end

  test "returns true when any field has content" do
    assert ObjectivePlanningInputBuilder.brief_present?({ "deliverable" => "Something" })
  end

  # --- field_present? ---

  test "returns true for non-empty list field" do
    brief = { "context" => ["Entry"] }
    assert ObjectivePlanningInputBuilder.field_present?(brief, "context")
  end

  test "returns false for empty list field" do
    brief = { "context" => [] }
    assert_not ObjectivePlanningInputBuilder.field_present?(brief, "context")
  end

  test "returns true for present string field" do
    brief = { "deliverable" => "Report" }
    assert ObjectivePlanningInputBuilder.field_present?(brief, "deliverable")
  end

  test "returns false for blank string field" do
    brief = { "deliverable" => "" }
    assert_not ObjectivePlanningInputBuilder.field_present?(brief, "deliverable")
  end

  # --- missing_fields ---

  test "returns required fields that are absent for given kind" do
    missing = ObjectivePlanningInputBuilder.missing_fields({}, "shopping")
    required = ObjectiveComposerTemplates.required_fields_for("shopping")
    assert_equal required.sort, missing.sort
  end

  test "returns empty when all required fields are filled" do
    brief = {
      "context" => ["Context info"],
      "success_criteria" => ["Criteria"],
      "deliverable" => "A list",
      "constraints" => ["Budget $100"],
      "preferences" => ["Brand X"]
    }
    missing = ObjectivePlanningInputBuilder.missing_fields(brief, "shopping")
    assert_empty missing
  end

  # --- filled_fields_count ---

  test "returns 0 for empty brief" do
    assert_equal 0, ObjectivePlanningInputBuilder.filled_fields_count({})
  end

  test "counts only fields with content" do
    brief = { "context" => ["Entry"], "deliverable" => "Report" }
    assert_equal 2, ObjectivePlanningInputBuilder.filled_fields_count(brief)
  end

  # --- humanize_field ---

  test "humanizes underscore field names" do
    assert_equal "Success criteria", ObjectivePlanningInputBuilder.humanize_field("success_criteria")
  end
end
