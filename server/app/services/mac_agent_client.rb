require "net/http"
require "json"

# Sends fire-and-forget trigger payloads to the Mac agent's WebhookListener.
# The Mac agent writes the payload to its dropzone and runs all webhook-scheduled
# missions, which can then call multi_step_search and write results back via the
# agent API.
class MacAgentClient
  WEBHOOK_URL = ENV.fetch("MAC_AGENT_WEBHOOK_URL", "http://localhost:8765")

  # Enqueues a task-search trigger on the Mac agent. Returns true if the webhook
  # acknowledged (HTTP 200), false on delivery failure.
  def trigger_task_search(task)
    payload = build_payload(task)
    uri = URI(WEBHOOK_URL)
    response = Net::HTTP.post(uri, payload.to_json, "Content-Type" => "application/json")
    response.is_a?(Net::HTTPSuccess)
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
