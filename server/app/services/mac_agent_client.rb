require "net/http"
require "json"

# Sends fire-and-forget trigger payloads to the Mac agent's WebhookListener.
# The Mac agent writes the payload to its dropzone and runs all webhook-scheduled
# missions, which can then call multi_step_search and write results back via the
# agent API.
class MacAgentClient
  # Prefer 127.0.0.1 over "localhost" to avoid IPv6 ::1 vs IPv4 mismatches with the Mac listener.
  WEBHOOK_URL = ENV.fetch("MAC_AGENT_WEBHOOK_URL", "http://127.0.0.1:8765")

  # Enqueues a task-search trigger on the Mac agent. Returns true if the webhook
  # acknowledged (HTTP 200), false on delivery failure.
  def trigger_task_search(task)
    payload = build_payload(task)
    uri = URI(WEBHOOK_URL)
    uri.path = "/" if uri.path.nil? || uri.path.empty?

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 3
    http.read_timeout = 15
    http.write_timeout = 15 if http.respond_to?(:write_timeout=)

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Connection"] = "close"
    request.body = payload.to_json

    response = http.request(request)
    ok = response.is_a?(Net::HTTPSuccess)
    Rails.logger.info("[MacAgentClient] Webhook task=#{task.id} http=#{response.code} ok=#{ok}")
    ok
  rescue => e
    Rails.logger.error("[MacAgentClient] Webhook failed for task=#{task.id}: #{e.message}")
    false
  end

  private

  def build_payload(task)
    {
      agentkvt: "run_task_search",
      task_id: task.id,
      objective_id: task.objective_id,
      description: task.description,
      # Default to a single search step. Webhook-triggered missions on the Mac
      # can read this file via read_dropzone_file and pass steps_json directly
      # to the multi_step_search tool.
      steps_json: [ { type: "search", query: task.description } ].to_json
    }
  end
end
