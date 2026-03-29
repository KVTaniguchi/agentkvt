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
  # When Ollama is unavailable or returns nothing usable, creates heuristic tasks so the
  # UI and Mac agent pipeline still have work items.
  def call(objective)
    raw = nil
    raw = @client.chat(
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: objective.goal }
      ],
      format: "json"
    )

    task_defs = normalize_task_defs(JSON.parse(raw))

    created = task_defs.first(5).filter_map do |t|
      description = t.is_a?(Hash) ? t["description"].to_s.strip : ""
      next if description.empty?

      task = objective.tasks.create!(description: description.truncate(500))
      TaskExecutorJob.perform_later(task.id.to_s)
      task
    end

    return created if created.any?

    Rails.logger.warn("[ObjectivePlanner] objective=#{objective.id} LLM returned no usable tasks; using fallback")
    fallback_tasks(objective)
  rescue JSON::ParserError, RuntimeError => e
    Rails.logger.error("[ObjectivePlanner] objective=#{objective.id} error=#{e.message} raw=#{raw.inspect}")
    fallback_tasks(objective)
  end

  private

  def normalize_task_defs(parsed)
    return parsed if parsed.is_a?(Array)
    return parsed["tasks"] if parsed.is_a?(Hash) && parsed["tasks"].is_a?(Array)

    raise "Expected JSON array"
  end

  def fallback_tasks(objective)
    goal = objective.goal.to_s.strip
    return [] if goal.empty?

    heuristic_descriptions(goal).filter_map do |description|
      task = objective.tasks.create!(description: description)
      TaskExecutorJob.perform_later(task.id.to_s)
      task
    end
  end

  # Splits multi-sentence goals into separate tasks; otherwise emits two standard research steps.
  def heuristic_descriptions(goal)
    parts = goal.split(/(?<=[.!?])\s+|\n+/).map(&:strip).reject(&:empty?)
    if parts.length >= 2 && parts.length <= 5 && parts.all? { |p| p.length >= 8 }
      return parts.first(5)
    end

    [
      "Research and compare options: #{goal.truncate(350)}",
      "Summarize constraints, deadlines, and recommended next steps for this objective"
    ]
  end
end
