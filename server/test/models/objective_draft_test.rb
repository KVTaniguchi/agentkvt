require "test_helper"
require "securerandom"

class ObjectiveDraftTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Draft WS", slug: "ws-#{SecureRandom.hex(4)}", server_mode: "personal")
  end

  def valid_draft(overrides = {})
    @workspace.objective_drafts.new({ template_key: "generic", status: "drafting" }.merge(overrides))
  end

  # --- Validations ---

  test "valid with required fields" do
    draft = valid_draft
    assert draft.valid?, draft.errors.full_messages.inspect
  end

  test "nil template_key is normalized to generic (never blank)" do
    draft = valid_draft(template_key: nil)
    draft.valid?
    assert_equal "generic", draft.template_key
    assert draft.valid?, draft.errors.full_messages.inspect
  end

  test "invalid template_key is normalized to generic" do
    draft = valid_draft(template_key: "bogus_template")
    draft.valid?
    assert_equal "generic", draft.template_key
    assert draft.valid?, draft.errors.full_messages.inspect
  end

  test "all valid template_keys accepted" do
    ObjectiveComposerTemplates::TEMPLATE_KEYS.each do |key|
      draft = valid_draft(template_key: key)
      assert draft.valid?, "Expected #{key} to be valid: #{draft.errors.full_messages}"
    end
  end

  test "invalid status rejected" do
    draft = valid_draft(status: "broken")
    assert_not draft.valid?
    assert draft.errors[:status].any?
  end

  test "valid statuses accepted" do
    %w[drafting finalized].each do |s|
      draft = valid_draft(status: s)
      assert draft.valid?, draft.errors.full_messages.inspect
    end
  end

  # --- Callbacks ---

  test "normalize_fields defaults blank status to drafting" do
    draft = valid_draft(status: "  ")
    draft.valid?
    assert_equal "drafting", draft.status
  end

  test "normalize_fields normalizes template_key to generic for unknown" do
    draft = @workspace.objective_drafts.new(status: "drafting")
    draft.template_key = "unknown_key"
    draft.valid?
    assert_equal "generic", draft.template_key
  end

  test "normalize_fields filters invalid missing_fields entries" do
    draft = valid_draft
    draft.missing_fields = ["context", "not_a_real_field", "success_criteria"]
    draft.valid?
    assert_includes draft.missing_fields, "context"
    assert_includes draft.missing_fields, "success_criteria"
    assert_not_includes draft.missing_fields, "not_a_real_field"
  end

  test "normalize_fields deduplicates missing_fields" do
    draft = valid_draft
    draft.missing_fields = ["context", "context"]
    draft.valid?
    assert_equal ["context"], draft.missing_fields
  end

  test "normalize_fields converts nil missing_fields to empty array" do
    draft = valid_draft
    draft.missing_fields = nil
    draft.valid?
    assert_equal [], draft.missing_fields
  end

  # --- Scopes ---

  test "chronological orders by created_at ascending" do
    draft1 = @workspace.objective_drafts.create!(template_key: "generic", status: "drafting")
    draft2 = @workspace.objective_drafts.create!(template_key: "shopping", status: "drafting")

    ids = @workspace.objective_drafts.chronological.map(&:id)
    assert ids.index(draft1.id) < ids.index(draft2.id)
  end

  test "stale_unfinalized returns old non-finalized drafts" do
    old_draft = @workspace.objective_drafts.create!(template_key: "generic", status: "drafting")
    old_draft.update_columns(created_at: 8.days.ago)
    recent_draft = @workspace.objective_drafts.create!(template_key: "generic", status: "drafting")
    finalized_draft = @workspace.objective_drafts.create!(template_key: "generic", status: "finalized")
    finalized_draft.update_columns(created_at: 8.days.ago)

    stale = ObjectiveDraft.stale_unfinalized
    assert_includes stale, old_draft
    assert_not_includes stale, recent_draft
    assert_not_includes stale, finalized_draft
  end

  # --- planner_summary ---

  test "planner_summary delegates to ObjectivePlanningInputBuilder.for_draft" do
    draft = @workspace.objective_drafts.create!(template_key: "generic", status: "drafting", suggested_goal: "Plan something")
    result = draft.planner_summary
    assert result.is_a?(String)
    assert result.include?("Plan something")
  end

  test "planner_summary accepts a goal override" do
    draft = @workspace.objective_drafts.create!(template_key: "generic", status: "drafting", suggested_goal: "Original goal")
    result = draft.planner_summary(goal: "Override goal")
    assert_includes result, "Override goal"
  end
end
