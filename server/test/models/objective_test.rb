require "test_helper"
require "securerandom"

class ObjectiveTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Test WS", slug: "ws-#{SecureRandom.hex(4)}", server_mode: "personal")
  end

  def valid_objective(overrides = {})
    @workspace.objectives.new({ goal: "Research best coffee shops", status: "pending", creation_source: "manual" }.merge(overrides))
  end

  # --- Validations ---

  test "valid with required fields" do
    obj = valid_objective
    assert obj.valid?, obj.errors.full_messages.inspect
  end

  test "invalid without goal" do
    obj = valid_objective(goal: nil)
    assert_not obj.valid?
    assert_includes obj.errors[:goal], "can't be blank"
  end

  test "invalid with bad status" do
    obj = valid_objective(status: "nonexistent")
    assert_not obj.valid?
    assert obj.errors[:status].any?
  end

  test "valid statuses are accepted" do
    %w[pending active completed archived].each do |s|
      obj = valid_objective(status: s)
      assert obj.valid?, "Expected #{s} to be valid: #{obj.errors.full_messages}"
    end
  end

  test "invalid creation_source rejected" do
    obj = valid_objective(creation_source: "alien")
    assert_not obj.valid?
    assert obj.errors[:creation_source].any?
  end

  test "valid creation_sources accepted" do
    %w[manual guided].each do |source|
      obj = valid_objective(creation_source: source)
      assert obj.valid?, obj.errors.full_messages.inspect
    end
  end

  test "invalid objective_kind rejected" do
    obj = valid_objective(objective_kind: "made_up")
    assert_not obj.valid?
    assert obj.errors[:objective_kind].any?
  end

  test "blank objective_kind is allowed" do
    obj = valid_objective(objective_kind: "")
    assert obj.valid?, obj.errors.full_messages.inspect
  end

  test "valid objective_kind accepted" do
    obj = valid_objective(objective_kind: "shopping")
    assert obj.valid?, obj.errors.full_messages.inspect
  end

  # --- Callbacks ---

  test "normalize_guided_fields strips and defaults creation_source" do
    obj = valid_objective(creation_source: "  ")
    obj.valid?
    assert_equal "manual", obj.creation_source
  end

  test "normalize_guided_fields strips objective_kind whitespace" do
    obj = valid_objective(objective_kind: "  shopping  ")
    obj.valid?
    assert_equal "shopping", obj.objective_kind
  end

  test "normalize_hands_config defaults nil hands_config to empty hash" do
    obj = valid_objective
    obj.hands_config = nil
    obj.valid?
    assert_equal({}, obj.hands_config)
  end

  test "normalize_hands_config defaults non-hash to empty hash" do
    obj = valid_objective
    obj.hands_config = "bad"
    obj.valid?
    assert_equal({}, obj.hands_config)
  end

  test "normalize_hands_config preserves valid hash" do
    obj = valid_objective
    obj.hands_config = { "key" => "value" }
    obj.valid?
    assert_equal({ "key" => "value" }, obj.hands_config)
  end

  # --- Scopes ---

  test "recent_first orders by priority desc then created_at desc" do
    obj1 = @workspace.objectives.create!(goal: "Low priority", status: "pending", priority: 1)
    obj2 = @workspace.objectives.create!(goal: "High priority", status: "pending", priority: 10)

    ids = @workspace.objectives.recent_first.map(&:id)
    assert ids.index(obj2.id) < ids.index(obj1.id)
  end

  # --- Associations ---

  test "destroys tasks when objective is destroyed" do
    obj = @workspace.objectives.create!(goal: "Clean up", status: "pending")
    obj.tasks.create!(description: "Do the thing", status: "pending")
    assert_difference -> { Task.count }, -1 do
      obj.destroy
    end
  end

  test "destroys research_snapshots when objective is destroyed" do
    obj = @workspace.objectives.create!(goal: "Research", status: "pending")
    obj.research_snapshots.create!(key: "finding", value: "Some info")
    assert_difference -> { ResearchSnapshot.count }, -1 do
      obj.destroy
    end
  end
end
