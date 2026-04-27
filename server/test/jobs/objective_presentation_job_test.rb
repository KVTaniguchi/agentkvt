require "test_helper"
require "net/http"
require "securerandom"

class ObjectivePresentationJobTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Presentation WS", slug: "ws-#{SecureRandom.hex(4)}", server_mode: "personal")
    @objective = @workspace.objectives.create!(goal: "Plan Paris trip", status: "active")
    @objective.tasks.create!(description: "Research flights", status: "completed", result_summary: "Found round trips from $600")
    @objective.research_snapshots.create!(key: "flight_price", value: "Round trips from $600")
  end

  def fake_ollama_http(content)
    http = Object.new
    http.define_singleton_method(:post) do |_path, _body, _headers|
      resp = Net::HTTPSuccess.new("1.1", "200", "OK")
      body = { "message" => { "content" => content }, "prompt_eval_count" => 10, "eval_count" => 5 }.to_json
      resp.instance_variable_set(:@body, body)
      resp.instance_variable_set(:@read, true)
      resp
    end
    http
  end

  def with_fake_ollama(content)
    original_start = Net::HTTP.method(:start)
    orig_mkdir_p = FileUtils.method(:mkdir_p)
    orig_file_open = File.method(:open)
    http = fake_ollama_http(content)
    Net::HTTP.define_singleton_method(:start) { |*_a, **_kw, &blk| blk.call(http) }
    FileUtils.define_singleton_method(:mkdir_p) { |_path| }
    File.define_singleton_method(:open) { |*_args, **_kw, &_blk| }
    yield
  ensure
    Net::HTTP.define_singleton_method(:start, &original_start)
    FileUtils.define_singleton_method(:mkdir_p, &orig_mkdir_p)
    File.define_singleton_method(:open, &orig_file_open)
  end

  test "updates objective presentation_json when builder succeeds" do
    fake_json = '{"layout":{"type":"vstack","children":[]}}'
    with_fake_ollama(fake_json) do
      ObjectivePresentationJob.new.perform(@objective.id.to_s)
    end

    @objective.reload
    assert_equal fake_json, @objective.presentation_json
    assert_not_nil @objective.presentation_generated_at
    assert_nil @objective.presentation_enqueued_at
  end

  test "does not update objective when builder returns nil due to invalid JSON" do
    with_fake_ollama("not valid json at all {{") do
      ObjectivePresentationJob.new.perform(@objective.id.to_s)
    end

    @objective.reload
    assert_nil @objective.presentation_json
  end

  test "does not update objective when layout key is missing" do
    with_fake_ollama('{"no_layout":true}') do
      ObjectivePresentationJob.new.perform(@objective.id.to_s)
    end

    @objective.reload
    assert_nil @objective.presentation_json
  end

  test "does nothing when objective is not found" do
    assert_nothing_raised do
      ObjectivePresentationJob.new.perform("999999")
    end
  end
end
