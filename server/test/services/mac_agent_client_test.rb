require "test_helper"
require "securerandom"
require "webrick"

class MacAgentClientTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(name: "Client WS", slug: "ws-#{SecureRandom.hex(4)}", server_mode: "personal")
    @objective = @workspace.objectives.create!(goal: "Test webhook", status: "active")
    @task = @objective.tasks.create!(description: "Search for data", status: "pending")
  end

  def with_webhook_server(status_code: 200, &block)
    received_requests = []
    server = WEBrick::HTTPServer.new(
      Port: 0,
      Logger: WEBrick::Log.new(File::NULL),
      AccessLog: []
    )
    port = server.config[:Port]
    server.mount_proc("/") do |req, res|
      # Cache body while the IO stream is still open (WEBrick closes it after this block)
      cached_body = req.body.to_s rescue ""
      req.define_singleton_method(:body) { cached_body }
      received_requests << req
      res.status = status_code
      res.body = "ok"
    end
    thread = Thread.new { server.start }
    block.call("http://127.0.0.1:#{port}", received_requests)
  ensure
    server.shutdown rescue nil
    thread&.join(2) rescue nil
  end

  # --- trigger_task_search returns false on network error ---

  test "returns false when connection refused" do
    client = MacAgentClient.new(webhook_url: "http://127.0.0.1:19999")
    result = client.trigger_task_search(@task)
    assert_equal false, result
  end

  # --- Returns true on 200 ---

  test "returns true when webhook responds 200" do
    with_webhook_server(status_code: 200) do |url, _requests|
      result = MacAgentClient.new(webhook_url: url).trigger_task_search(@task)
      assert_equal true, result
    end
  end

  # --- Returns false on non-200 ---

  test "returns false when webhook responds non-2xx" do
    with_webhook_server(status_code: 500) do |url, _requests|
      result = MacAgentClient.new(webhook_url: url).trigger_task_search(@task)
      assert_equal false, result
    end
  end

  # --- HMAC signature ---

  test "attaches X-Webhook-Signature when secret is configured" do
    with_webhook_server do |url, requests|
      with_env("MAC_AGENT_WEBHOOK_SECRET", "mysecret") do
        MacAgentClient.new(webhook_url: url).trigger_task_search(@task)
      end

      assert_equal 1, requests.size
      sig = requests.first["x-webhook-signature"]
      assert_not_nil sig, "Expected X-Webhook-Signature header"
      assert_match(/^sha256=/, sig)
    end
  end

  test "HMAC signature is correct sha256" do
    secret = "testsecret"
    with_webhook_server do |url, requests|
      with_env("MAC_AGENT_WEBHOOK_SECRET", secret) do
        MacAgentClient.new(webhook_url: url).trigger_task_search(@task)
      end

      req = requests.first
      body = req.body
      expected_sig = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, body)}"
      assert_equal expected_sig, req["x-webhook-signature"]
    end
  end

  test "does not attach X-Webhook-Signature when secret is not configured" do
    with_webhook_server do |url, requests|
      with_env("MAC_AGENT_WEBHOOK_SECRET", nil) do
        MacAgentClient.new(webhook_url: url).trigger_task_search(@task)
      end

      assert_nil requests.first["x-webhook-signature"]
    end
  end

  # --- Payload shape ---

  test "payload includes required task fields" do
    with_webhook_server do |url, requests|
      MacAgentClient.new(webhook_url: url).trigger_task_search(@task)
    end

    with_webhook_server do |url, requests|
      MacAgentClient.new(webhook_url: url).trigger_task_search(@task)
      body = JSON.parse(requests.first.body)

      assert_equal "run_task_search", body["agentkvt"]
      assert_equal @task.id, body["task_id"]
      assert_equal @objective.id, body["objective_id"]
      assert_equal @task.description, body["description"]
      assert body.key?("steps_json")
      assert body.key?("done_when")
      assert body.key?("objective_goal")
    end
  end

  test "payload truncates objective_goal to 20000 bytes" do
    @objective.update_columns(goal: "a" * 25_000)
    with_webhook_server do |url, requests|
      MacAgentClient.new(webhook_url: url).trigger_task_search(@task)
      body = JSON.parse(requests.first.body)
      assert body["objective_goal"].bytesize <= 20_000
    end
  end

  test "payload includes objective_brief when brief_json is present" do
    @objective.update_columns(brief_json: { "context" => ["some context"] })
    with_webhook_server do |url, requests|
      MacAgentClient.new(webhook_url: url).trigger_task_search(@task)
      body = JSON.parse(requests.first.body)
      assert body.key?("objective_brief")
    end
  end

  test "payload omits objective_brief when brief_json is empty" do
    @objective.update_columns(brief_json: {})
    with_webhook_server do |url, requests|
      MacAgentClient.new(webhook_url: url).trigger_task_search(@task)
      body = JSON.parse(requests.first.body)
      assert_not body.key?("objective_brief")
    end
  end

  private

  def with_env(key, value, &block)
    original = ENV[key]
    value.nil? ? ENV.delete(key) : (ENV[key] = value)
    block.call
  ensure
    original.nil? ? ENV.delete(key) : (ENV[key] = original)
  end
end
