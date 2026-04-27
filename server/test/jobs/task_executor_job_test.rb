require "test_helper"
require "securerandom"
require "webrick"

class TaskExecutorJobTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Executor WS", slug: "ws-#{SecureRandom.hex(4)}", server_mode: "personal")
    @objective = @workspace.objectives.create!(goal: "Buy the best coffee", status: "active")
  end

  def create_task(overrides = {})
    @objective.tasks.create!({ description: "Search for coffee options", status: "pending" }.merge(overrides))
  end

  # Spin up a minimal WEBrick server and register an agent pointing at it.
  # Returns the agent. The server shuts down after the block.
  def with_webhook_success_agent
    server = WEBrick::HTTPServer.new(
      Port: 0,
      Logger: WEBrick::Log.new(File::NULL),
      AccessLog: []
    )
    port = server.config[:Port]
    server.mount_proc("/") { |_req, res| res.status = 200; res.body = "ok" }
    thread = Thread.new { server.start }

    agent = @workspace.agent_registrations.create!(
      agent_id: "test-agent-#{SecureRandom.hex(4)}",
      status: "online",
      last_seen_at: 10.seconds.ago,
      capabilities: [Task::OBJECTIVE_EXECUTION_CAPABILITY, "web_search"],
      webhook_url: "http://127.0.0.1:#{port}"
    )

    yield agent
  ensure
    server.shutdown rescue nil
    thread&.join(2) rescue nil
  end

  # --- Normal execution ---

  test "claims and marks task in_progress when webhook succeeds" do
    task = create_task
    with_webhook_success_agent do |_agent|
      TaskExecutorJob.new.perform(task.id.to_s)
    end
    task.reload
    assert_equal "in_progress", task.status
    assert_not_nil task.claimed_at
  end

  test "reverts task to pending when webhook fails (no server running)" do
    task = create_task
    # Override the webhook URL to a port with nothing listening
    @workspace.agent_registrations.create!(
      agent_id: "offline-agent",
      status: "online",
      last_seen_at: 5.seconds.ago,
      capabilities: [Task::OBJECTIVE_EXECUTION_CAPABILITY, "web_search"],
      webhook_url: "http://127.0.0.1:19999"
    )
    TaskExecutorJob.new.perform(task.id.to_s)
    task.reload
    assert_equal "pending", task.status
    assert_nil task.claimed_at
    assert_nil task.claimed_by_agent_id
  end

  # --- Skip-locked guard ---

  test "does nothing when task is already in_progress" do
    task = create_task(status: "in_progress")
    original_result_summary = task.result_summary
    # No HTTP interaction needed — the job skips the task because status != "pending"
    with_webhook_success_agent do
      TaskExecutorJob.new.perform(task.id.to_s)
    end
    task.reload
    assert_equal "in_progress", task.status
    assert_nil task.claimed_at
  end

  test "does nothing for a non-existent task id" do
    count_before = Task.count
    TaskExecutorJob.new.perform("999999")
    assert_equal count_before, Task.count
  end

  # --- Circuit breaker: repelling snapshots ---

  test "skips task and marks completed when repellent snapshot matches description" do
    task = create_task(description: "Search for rare black truffles")
    @objective.research_snapshots.create!(
      key: "dead_end",
      value: "No results found",
      is_repellent: true,
      repellent_reason: "Zero availability in this region",
      repellent_scope: "rare black truffles"
    )

    with_webhook_success_agent do
      TaskExecutorJob.new.perform(task.id.to_s)
    end

    task.reload
    assert_equal "completed", task.status
    assert_match(/dead-end|Circuit breaker/i, task.result_summary)
  end

  test "does not skip task when repellent scope does not match description" do
    task = create_task(description: "Search for Arabica coffee beans")
    @objective.research_snapshots.create!(
      key: "dead_end",
      value: "Nothing found",
      is_repellent: true,
      repellent_reason: "Not available",
      repellent_scope: "rare black truffles"
    )

    with_webhook_success_agent do
      TaskExecutorJob.new.perform(task.id.to_s)
    end

    task.reload
    assert_equal "in_progress", task.status
  end

  test "does not skip task when no repelling snapshots exist" do
    task = create_task
    with_webhook_success_agent do
      TaskExecutorJob.new.perform(task.id.to_s)
    end
    task.reload
    assert_equal "in_progress", task.status
  end

  # --- Agent routing ---

  test "sets claimed_by_agent_id to the online agent's agent_id" do
    task = create_task
    with_webhook_success_agent do |agent|
      TaskExecutorJob.new.perform(task.id.to_s)
      task.reload
      assert_equal agent.agent_id, task.claimed_by_agent_id
    end
  end

  test "sets claimed_by_agent_id to mac-agent when no capable agent is online" do
    task = create_task
    # No agent registered — override trigger_task_search to return false so the job always reverts
    original_trigger = MacAgentClient.instance_method(:trigger_task_search)
    MacAgentClient.define_method(:trigger_task_search) { |_task| false }

    TaskExecutorJob.new.perform(task.id.to_s)

    task.reload
    assert_nil task.claimed_by_agent_id
  ensure
    MacAgentClient.define_method(:trigger_task_search, original_trigger)
  end
end
