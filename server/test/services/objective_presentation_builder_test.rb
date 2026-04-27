require "test_helper"
require "securerandom"

class ObjectivePresentationBuilderTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Presentation WS", slug: "ws-#{SecureRandom.hex(4)}", server_mode: "personal")
    @objective = @workspace.objectives.create!(goal: "Find best laptops", status: "active")
  end

  def mock_client(response)
    client = Object.new
    client.define_singleton_method(:chat) { |**_kwargs| response }
    client
  end

  # --- Returns nil edge cases ---

  test "returns nil when objective has no snapshots and no tasks" do
    result = ObjectivePresentationBuilder.new(client: mock_client("{}")).call(@objective)
    assert_nil result
  end

  # --- Happy path ---

  test "returns raw JSON string on success" do
    @objective.research_snapshots.create!(key: "top_laptop", value: "MacBook Pro M4 at $1299")
    valid_json = '{"layout":{"type":"vstack","children":[]}}'
    client = mock_client(valid_json)

    result = ObjectivePresentationBuilder.new(client: client).call(@objective)
    assert_equal valid_json, result
  end

  test "includes completed task descriptions in Ollama input" do
    task = @objective.tasks.create!(description: "Find best laptops under $1500", status: "completed", result_summary: "MacBook Pro M4 recommended")
    @objective.research_snapshots.create!(key: "finding", value: "Good value options found")

    captured_messages = nil
    client = Object.new
    client.define_singleton_method(:chat) do |messages:, **_kwargs|
      captured_messages = messages
      '{"layout":{"type":"vstack","children":[]}}'
    end

    ObjectivePresentationBuilder.new(client: client).call(@objective)
    user_content = captured_messages.find { |m| m[:role] == "user" }&.dig(:content)
    assert_match(/Find best laptops under \$1500/, user_content)
    assert_match(/MacBook Pro M4 recommended/, user_content)
  end

  test "includes research snapshots in Ollama input" do
    @objective.research_snapshots.create!(key: "price_range", value: "$800 to $1500")

    captured_messages = nil
    client = Object.new
    client.define_singleton_method(:chat) do |messages:, **_kwargs|
      captured_messages = messages
      '{"layout":{"type":"vstack","children":[]}}'
    end

    ObjectivePresentationBuilder.new(client: client).call(@objective)
    user_content = captured_messages.find { |m| m[:role] == "user" }&.dig(:content)
    assert_match(/price_range/, user_content)
    assert_match(/\$800 to \$1500/, user_content)
  end

  # --- Error handling ---

  test "returns nil when Ollama returns invalid JSON" do
    @objective.research_snapshots.create!(key: "finding", value: "Some result")
    client = mock_client("not json at all {{{")
    result = ObjectivePresentationBuilder.new(client: client).call(@objective)
    assert_nil result
  end

  test "returns nil when layout key is missing from response" do
    @objective.research_snapshots.create!(key: "finding", value: "Some result")
    client = mock_client('{"something_else": {}}')
    result = ObjectivePresentationBuilder.new(client: client).call(@objective)
    assert_nil result
  end

  test "returns nil when root type is not vstack" do
    @objective.research_snapshots.create!(key: "finding", value: "Some result")
    client = mock_client('{"layout":{"type":"hstack","children":[]}}')
    result = ObjectivePresentationBuilder.new(client: client).call(@objective)
    assert_nil result
  end

  # --- Ranked snapshots: positive feedback surfaced first ---

  test "positive-feedback snapshots appear before negative ones" do
    snap_good = @objective.research_snapshots.create!(key: "good_finding", value: "Great option found")
    snap_bad  = @objective.research_snapshots.create!(key: "bad_finding", value: "Mediocre option")

    ResearchSnapshotFeedback.create!(
      workspace: @workspace, objective: @objective, research_snapshot: snap_good,
      role: "user", rating: "good"
    )
    ResearchSnapshotFeedback.create!(
      workspace: @workspace, objective: @objective, research_snapshot: snap_bad,
      role: "user", rating: "bad"
    )

    captured_messages = nil
    client = Object.new
    client.define_singleton_method(:chat) do |messages:, **_kwargs|
      captured_messages = messages
      '{"layout":{"type":"vstack","children":[]}}'
    end

    ObjectivePresentationBuilder.new(client: client).call(@objective)
    user_content = captured_messages.find { |m| m[:role] == "user" }&.dig(:content)
    good_pos = user_content.index("good_finding")
    bad_pos  = user_content.index("bad_finding")
    assert good_pos < bad_pos, "Expected positively-rated snapshot to appear before negatively-rated one"
  end
end
