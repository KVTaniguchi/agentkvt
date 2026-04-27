require "test_helper"
require "securerandom"

class TaskTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Task WS", slug: "ws-#{SecureRandom.hex(4)}", server_mode: "personal")
    @objective = @workspace.objectives.create!(goal: "Buy groceries", status: "active")
  end

  def build_task(overrides = {})
    @objective.tasks.new({ description: "Search for options", status: "pending" }.merge(overrides))
  end

  # --- Validations ---

  test "valid task with required fields" do
    task = build_task
    assert task.valid?, task.errors.full_messages.inspect
  end

  test "invalid without description" do
    task = build_task(description: nil)
    assert_not task.valid?
    assert task.errors[:description].any?
  end

  test "invalid status rejected" do
    task = build_task(status: "flying")
    assert_not task.valid?
    assert task.errors[:status].any?
  end

  test "all valid statuses accepted" do
    Task::STATUSES.each do |s|
      task = build_task(status: s)
      assert task.valid?, "Expected #{s} to be valid: #{task.errors.full_messages}"
    end
  end

  # --- inferred_task_kind ---

  test "infers action for purchase verbs" do
    %w[buy purchase order book reserve].each do |verb|
      assert_equal "action", Task.inferred_task_kind("#{verb} something"), "Expected 'action' for '#{verb}'"
    end
  end

  test "infers action for notification verbs" do
    assert_equal "action", Task.inferred_task_kind("send email to confirm")
    assert_equal "action", Task.inferred_task_kind("create reminder for tomorrow")
  end

  test "infers synthesis for summary/recommendation verbs" do
    assert_equal "synthesis", Task.inferred_task_kind("final recommendation on options")
    assert_equal "synthesis", Task.inferred_task_kind("summarize findings")
    assert_equal "synthesis", Task.inferred_task_kind("synthesize results")
  end

  test "defaults to research for unmatched descriptions" do
    assert_equal "research", Task.inferred_task_kind("compare prices at local stores")
    assert_equal "research", Task.inferred_task_kind("")
  end

  # --- normalized_task_kind ---

  test "normalizes valid task kind" do
    assert_equal "action", Task.normalized_task_kind("action")
    assert_equal "synthesis", Task.normalized_task_kind("synthesis")
    assert_equal "research", Task.normalized_task_kind("research")
  end

  test "defaults unknown task kind to research" do
    assert_equal "research", Task.normalized_task_kind("bogus")
    assert_equal "research", Task.normalized_task_kind(nil)
    assert_equal "research", Task.normalized_task_kind("")
  end

  # --- normalize_allowed_tool_ids ---

  test "always includes base tool ids" do
    ids = Task.normalize_allowed_tool_ids([], task_kind: "research", description: "find info")
    Task::OBJECTIVE_BASE_TOOL_IDS.each do |base_id|
      assert_includes ids, base_id
    end
  end

  test "research tasks include multi_step_search by default" do
    ids = Task.normalize_allowed_tool_ids([], task_kind: "research", description: "find info")
    assert_includes ids, "multi_step_search"
  end

  test "explicit tool ids are preserved" do
    ids = Task.normalize_allowed_tool_ids(["github_agent"], task_kind: "action", description: "check github")
    assert_includes ids, "github_agent"
  end

  test "deduplicates tool ids" do
    ids = Task.normalize_allowed_tool_ids(["read_dropzone_file"], task_kind: "research", description: "find info")
    assert_equal ids.uniq, ids
  end

  # --- inferred_action_tool_ids ---

  test "infers site_scout for browser/cart tasks" do
    ids = Task.inferred_action_tool_ids("buy from website cart")
    assert_includes ids, "site_scout"
  end

  test "infers send_notification_email for email tasks" do
    ids = Task.inferred_action_tool_ids("notify me by email when done")
    assert_includes ids, "send_notification_email"
  end

  test "infers write_reminder for reminder tasks" do
    ids = Task.inferred_action_tool_ids("create reminder for pickup")
    assert_includes ids, "write_reminder"
  end

  test "infers read_calendar for calendar tasks" do
    ids = Task.inferred_action_tool_ids("check calendar for availability")
    assert_includes ids, "read_calendar"
  end

  test "infers github_agent for github tasks" do
    ids = Task.inferred_action_tool_ids("open pull request on github repo")
    assert_includes ids, "github_agent"
  end

  test "defaults to site_scout when no specific action matched" do
    ids = Task.inferred_action_tool_ids("do something vague")
    assert_includes ids, "site_scout"
  end

  # --- execution_contract ---

  test "execution_contract returns a complete contract hash" do
    contract = Task.execution_contract(description: "Research best laptops")
    assert_equal "research", contract[:task_kind]
    assert contract[:allowed_tool_ids].is_a?(Array)
    assert contract[:required_capabilities].is_a?(Array)
    assert contract[:done_when].is_a?(String)
    assert contract[:done_when].present?
  end

  test "execution_contract respects explicit task_kind" do
    contract = Task.execution_contract(description: "Do something", task_kind: "synthesis")
    assert_equal "synthesis", contract[:task_kind]
  end

  # --- default_required_capabilities ---

  test "always includes objective_research capability" do
    caps = Task.default_required_capabilities([])
    assert_includes caps, "objective_research"
  end

  test "includes web_search capability for multi_step_search tool" do
    caps = Task.default_required_capabilities(["multi_step_search"])
    assert_includes caps, "web_search"
  end

  # --- normalize_required_capabilities ---

  test "always prepends objective_research" do
    caps = Task.normalize_required_capabilities(["email"])
    assert_equal "objective_research", caps.first
  end

  test "deduplicates capabilities" do
    caps = Task.normalize_required_capabilities(["objective_research", "email"])
    assert_equal caps.uniq, caps
  end

  # --- default_done_when ---

  test "research done_when mentions snapshots" do
    assert_match(/snapshot/, Task.default_done_when("research"))
  end

  test "action done_when mentions action" do
    assert_match(/action/i, Task.default_done_when("action"))
  end

  test "synthesis done_when mentions snapshot" do
    assert_match(/snapshot/i, Task.default_done_when("synthesis"))
  end

  # --- Callbacks: apply_default_execution_contract on create ---

  test "creates task with inferred defaults applied" do
    task = @objective.tasks.create!(description: "Search for best deals", status: "pending")
    assert_equal "research", task.task_kind
    assert_includes task.allowed_tool_ids, "multi_step_search"
    assert_includes task.required_capabilities, "objective_research"
    assert task.done_when.present?
  end

  # --- Scopes ---

  test "initial_plan returns tasks without source_feedback" do
    task = @objective.tasks.create!(description: "Initial search", status: "pending")
    assert_includes @objective.tasks.initial_plan, task
  end

  test "follow_up excludes tasks without source_feedback" do
    task = @objective.tasks.create!(description: "Initial search", status: "pending")
    assert_not_includes @objective.tasks.follow_up, task
  end
end
