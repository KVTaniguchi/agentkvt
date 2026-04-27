require "test_helper"
require "net/http"
require "securerandom"

class ObjectivePlannerJobTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Planner WS", slug: "ws-#{SecureRandom.hex(4)}", server_mode: "personal")
    @objective = @workspace.objectives.create!(goal: "Plan a trip to Paris", status: "pending")
  end

  test "does nothing when objective is not found" do
    assert_nothing_raised do
      ObjectivePlannerJob.new.perform("999999")
    end
  end

  test "finds the objective and calls ObjectivePlanner" do
    ollama_tasks_json = [
      { "description" => "Research Paris hotels", "task_kind" => "research" },
      { "description" => "Check flight prices", "task_kind" => "research" }
    ].to_json
    ollama_response = {
      "message" => { "content" => ollama_tasks_json },
      "prompt_eval_count" => 50,
      "eval_count" => 20
    }.to_json

    fake_http = Object.new
    fake_http.define_singleton_method(:post) do |_path, _body, _headers|
      resp = Net::HTTPSuccess.new("1.1", "200", "OK")
      resp.instance_variable_set(:@body, ollama_response)
      resp.instance_variable_set(:@read, true)
      resp
    end

    original_start = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |*_a, **_kw, &blk| blk.call(fake_http) }
    orig_mkdir_p = FileUtils.method(:mkdir_p)
    FileUtils.define_singleton_method(:mkdir_p) { |_path| }
    orig_file_open = File.method(:open)
    File.define_singleton_method(:open) { |*_args, **_kw, &_blk| }

    # ObjectivePlanner tops up to minimum_task_count (≥4 for simple goals); assert at least 2 from the LLM
    pre_count = @objective.tasks.count
    ObjectivePlannerJob.new.perform(@objective.id.to_s)
    assert_operator @objective.reload.tasks.count, :>=, pre_count + 2
  ensure
    Net::HTTP.define_singleton_method(:start, &original_start)
    FileUtils.define_singleton_method(:mkdir_p, &orig_mkdir_p)
    File.define_singleton_method(:open, &orig_file_open)
  end
end
