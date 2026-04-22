class ObjectivePresentationBuilder
  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a UI layout generator for iOS. Given research findings from an AI agent, produce a JSON layout
    that presents the findings clearly on a mobile screen.

    Respond with ONLY valid JSON matching this structure:
    {"layout":{"type":"vstack","children":[...]}}

    Node types and their fields:
    - vstack: {"type":"vstack","children":[...]}
    - hstack: {"type":"hstack","children":[...]}
    - card:   {"type":"card","title":"optional section heading","children":[...]}
    - text:   {"type":"text","content":"string","style":"headline|body|caption"} (style defaults to body)
    - stat:   {"type":"stat","label":"string","value":"string","delta":"optional change note"}
    - badge:  {"type":"badge","label":"string","color":"green|red|orange|blue|gray"}
    - link:   {"type":"link","label":"string","url":"string"}
    - divider: {"type":"divider"}

    Rules:
    - Root must be a vstack
    - Maximum 3 levels of nesting
    - Use cards to group related findings into sections
    - Use stats for key metrics and quantitative findings
    - Use badges for status labels, tags, and categories
    - Include a link node at the bottom of a card if the research finding references a specific actionable URL
    - Keep all text concise — this is a mobile UI
    - Respond with ONLY the JSON object, no markdown fences, no explanation
  PROMPT

  def initialize(client: OllamaClient.new)
    @client = client
  end

  # Generates a UINode JSON layout for the given objective's research results.
  # Returns the raw JSON string on success, nil if there is nothing to render or on error.
  def call(objective)
    return nil if objective.research_snapshots.empty? && objective.tasks.empty?

    input = build_input(objective)
    raw = @client.chat(
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: input }
      ],
      format: "json",
      task: "objective-presentation",
      options: { num_ctx: 8192, think: false }
    )

    parsed = JSON.parse(raw)
    layout = parsed["layout"]
    raise "Missing layout key" unless layout.is_a?(Hash)
    raise "Root must be vstack" unless layout["type"] == "vstack"

    raw
  rescue JSON::ParserError, RuntimeError => e
    Rails.logger.error("[ObjectivePresentationBuilder] objective=#{objective.id} error=#{e.message}")
    nil
  end

  private

  def build_input(objective)
    lines = ["Objective: #{objective.goal}", ""]

    completed_tasks = objective.tasks.where(status: "completed")
    if completed_tasks.any?
      lines << "Completed research tasks:"
      completed_tasks.each do |task|
        lines << "- #{task.description}"
        lines << "  Result: #{task.result_summary}" if task.result_summary.present?
      end
      lines << ""
    end

    snapshots = ranked_snapshots(objective)
    if snapshots.any?
      lines << "Research findings:"
      snapshots.each do |snap|
        line = "#{snap.key}: #{snap.value}"
        line += " (change: #{snap.delta_note})" if snap.delta_note.present?
        if snap.negative_feedback_count.positive?
          line += " (needs verification due to negative feedback)"
        end
        lines << line
      end
    end

    rated_feedback = objective.research_snapshot_feedbacks.includes(:research_snapshot).recent_first.limit(8)
    if rated_feedback.any?
      lines << ""
      lines << "Rated findings:"
      rated_feedback.each do |entry|
        snapshot = entry.research_snapshot
        next unless snapshot

        line = "- #{entry.rating.upcase}: #{snapshot.key}: #{snapshot.value}"
        line += " [reason: #{entry.reason}]" if entry.reason.present?
        lines << line
      end
    end

    lines.join("\n")
  end

  def ranked_snapshots(objective)
    objective.research_snapshots.includes(:feedback_entries).sort_by do |snap|
      score = (snap.positive_feedback_count * 10) - (snap.negative_feedback_count * 10)
      [-score, -(snap.checked_at.to_i)]
    end
  end
end
