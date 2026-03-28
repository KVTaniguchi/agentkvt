class ObjectivePlanner
  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a research task planner. Given a goal, output a JSON array of 2–5 research tasks.
    Each element must be an object with a single key "description" whose value is a concise action string.
    Respond with ONLY valid JSON — no markdown fences, no prose, no explanation.
    Example: [{"description":"Search for hotel options near the convention center"},{"description":"Compare flight prices from PHL to SAN for the target dates"}]
  PROMPT

  def initialize(client: OllamaClient.new)
    @client = client
  end

  # Prompts the LLM to decompose +objective.goal+ into Tasks and persists them.
  # Returns the array of created Task records (empty on parse failure).
  def call(objective)
    raw = @client.chat(
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: objective.goal }
      ],
      format: "json"
    )

    task_defs = JSON.parse(raw)
    raise "Expected JSON array" unless task_defs.is_a?(Array)

    task_defs.first(5).filter_map do |t|
      description = t["description"].to_s.strip
      next if description.empty?

      task = objective.tasks.create!(description: description)
      TaskExecutorJob.perform_later(task.id.to_s)
      task
    end
  rescue JSON::ParserError, RuntimeError => e
    Rails.logger.error("[ObjectivePlanner] objective=#{objective.id} error=#{e.message} raw=#{raw.inspect}")
    []
  end
end
