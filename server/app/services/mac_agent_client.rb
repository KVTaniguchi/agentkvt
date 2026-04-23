require "net/http"
require "json"

# Sends fire-and-forget trigger payloads to the Mac agent's WebhookListener.
# The Mac agent writes the payload to its dropzone and runs all webhook-scheduled
# missions, which can then call multi_step_search and write results back via the
# agent API.
class MacAgentClient
  # Prefer 127.0.0.1 over "localhost" to avoid IPv6 ::1 vs IPv4 mismatches with the Mac listener.
  DEFAULT_WEBHOOK_URL = ENV.fetch("MAC_AGENT_WEBHOOK_URL", "http://127.0.0.1:8765")

  def initialize(webhook_url: nil)
    @webhook_url = webhook_url.presence || DEFAULT_WEBHOOK_URL
  end

  # Enqueues a task-search trigger on the Mac agent. Returns true if the webhook
  # acknowledged (HTTP 200), false on delivery failure.
  def trigger_task_search(task)
    payload = build_payload(task)
    uri = URI(@webhook_url)
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
    Rails.logger.info("[MacAgentClient] Webhook task=#{task.id} url=#{uri} http=#{response.code} ok=#{ok}")
    ok
  rescue => e
    Rails.logger.error("[MacAgentClient] Webhook failed task=#{task.id} url=#{@webhook_url} error=#{e.class}: #{e.message}")
    false
  end

  private

  def build_payload(task)
    goal = task.objective&.goal.to_s
    payload = {
      agentkvt: "run_task_search",
      task_id: task.id,
      objective_id: task.objective_id,
      description: task.description,
      task_kind: task.task_kind,
      allowed_tool_ids: task.allowed_tool_ids,
      required_capabilities: task.required_capabilities,
      done_when: task.done_when.to_s.byteslice(0, 500),
      # Full parent objective so the Mac agent can ground research/synthesis (task.description alone is often a narrow sub-line).
      objective_goal: goal.byteslice(0, 20_000),
      # Default to a single search step. Webhook-triggered missions on the Mac
      # can read this file via read_dropzone_file and pass steps_json directly
      # to the multi_step_search tool.
      steps_json: [ { type: "search", query: task.description } ].to_json
    }
    brief = task.objective&.brief_json
    payload[:objective_brief] = brief if brief.present?
    payload
  end
end
