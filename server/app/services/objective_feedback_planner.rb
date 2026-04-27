class ObjectiveFeedbackPlanner
  MAX_TASKS = 3
  REALIGNMENT_CYCLE_INTERVAL = 3

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a follow-up research task planner. Given an existing objective, current findings, and new user feedback,
    output a JSON array of 1-3 concrete next-step tasks for an AI research agent.

    Each element must be an object with exactly one key: "description".

    Rules:
    - Focus on what the user wants to happen next.
    - Avoid repeating already completed work unless the user is explicitly challenging or revisiting it.
    - Preserve or build on positively rated findings when they are still relevant.
    - Do not trust negatively rated findings as strong evidence without re-verifying them.
    - If a negative rating says a finding is wrong, stale, or outdated, prefer verification or refresh tasks.
    - If a negative rating says a finding is vague, weak, or irrelevant, prefer narrower comparison or gap-closing tasks.
    - Prefer specific comparison, verification, synthesis, or gap-closing tasks.
    - If the user wants a final recommendation or next move, prefer exactly 1 synthesis task that turns the current findings into a decision.
    - Only add a second task for a recommendation-style request if one specific missing fact clearly blocks the decision.
    - Keep each description concise and actionable.
    - Respond with ONLY valid JSON and no explanation.
  PROMPT

  def initialize(client: OllamaClient.new)
    @client = client
  end

  def call(feedback)
    objective = feedback.objective
    raw = nil
    raw = @client.chat(
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: build_input(feedback) }
      ],
      format: "json",
      task: "objective-follow-up",
      options: { num_ctx: 8192, think: false }
    )

    task_defs = normalize_task_defs(JSON.parse(raw))
    descriptions = task_defs.filter_map do |task_def|
      next unless task_def.is_a?(Hash)
      description = task_def["description"].to_s.strip
      next if description.empty?
      description
    end.uniq
    descriptions = normalize_descriptions(feedback, descriptions).first(MAX_TASKS)

    tasks = descriptions.any? ? persist_tasks(feedback, descriptions) : fallback_tasks(feedback)
    realignment = maybe_insert_realignment_task(feedback)
    tasks + Array(realignment)
  rescue JSON::ParserError, RuntimeError => error
    Rails.logger.error(
      "[ObjectiveFeedbackPlanner] feedback=#{feedback.id} objective=#{feedback.objective_id} error=#{error.message} raw=#{raw.inspect}"
    )
    fallback_tasks(feedback)
  end

  private

  def normalize_task_defs(parsed)
    return parsed if parsed.is_a?(Array)
    return parsed["tasks"] if parsed.is_a?(Hash) && parsed["tasks"].is_a?(Array)

    raise "Expected JSON array"
  end

  def persist_tasks(feedback, descriptions)
    task_status = task_status_for(descriptions)
    descriptions.filter_map do |description|
      next if description.blank?

      feedback.objective.tasks.create!(
        description: description.truncate(500),
        status: task_status,
        source_feedback: feedback
      )
    end
  end

  def fallback_tasks(feedback)
    persist_tasks(feedback, fallback_descriptions(feedback))
  end

  def task_status_for(descriptions)
    descriptions.length > 1 ? "proposed" : "pending"
  end

  def fallback_descriptions(feedback)
    content = feedback.content.to_s.strip.truncate(260)
    anchored_key = feedback.research_snapshot&.key
    anchored_task = feedback.task&.description&.truncate(160)

    primary = case feedback.feedback_kind
    when "compare_options"
      "Compare the strongest options related to this feedback: #{content}"
    when "challenge_result"
      "Re-check the earlier findings and challenge weak assumptions based on this feedback: #{content}"
    when "clarify_gaps"
      "Fill the key information gaps raised by this feedback: #{content}"
    when "final_recommendation"
      "Turn the current research into a concrete recommendation that addresses: #{content}"
    else
      "Continue the research for this objective based on the user's follow-up: #{content}"
    end

    secondary =
      if anchored_key.present?
        "Dig deeper into the finding '#{anchored_key}' and update it based on the user's feedback"
      elsif anchored_task.present?
        "Extend the task '#{anchored_task}' with a focused follow-up that addresses the user's feedback"
      end

    return [primary] if recommendation_feedback?(feedback)

    [primary, secondary].compact
  end

  def normalize_descriptions(feedback, descriptions)
    cleaned = descriptions.map(&:strip).reject(&:blank?)
    return cleaned if cleaned.empty?
    return cleaned unless recommendation_feedback?(feedback)

    preferred = cleaned.find { |description| synthesis_description?(description) } || cleaned.first
    [preferred]
  end

  def recommendation_feedback?(feedback)
    feedback.feedback_kind == "final_recommendation"
  end

  def synthesis_description?(description)
    normalized = description.to_s.downcase
    normalized.include?("recommend") ||
      normalized.include?("summary") ||
      normalized.include?("synthes") ||
      normalized.include?("next move") ||
      normalized.include?("turn the current research into")
  end

  def maybe_insert_realignment_task(feedback)
    objective = feedback.objective
    return unless (objective.objective_feedbacks.count % REALIGNMENT_CYCLE_INTERVAL).zero?

    objective.tasks.create!(
      description: realignment_description(objective),
      task_kind: "synthesis",
      status: "proposed",
      source_feedback: feedback
    )
  end

  def realignment_description(objective)
    brief = ObjectivePlanningInputBuilder.normalize_brief(objective.brief_json)
    criteria = brief["success_criteria"].first(2).join("; ")
    constraints = brief["constraints"].first(2).join("; ")

    parts = [ "Review all research findings and completed tasks for this objective." ]
    parts << "Compare current progress against these success criteria: #{criteria}." if criteria.present?
    parts << "Honor these constraints: #{constraints}." if constraints.present?
    parts << "Flag any areas where the research has drifted from the original goal and identify the single most important gap or course correction needed."
    parts.join(" ").truncate(500)
  end

  def build_input(feedback)
    objective = feedback.objective
    brief = ObjectivePlanningInputBuilder.normalize_brief(objective.brief_json)

    lines = [
      "Objective: #{objective.goal}",
      "Objective summary:",
      ObjectivePlanningInputBuilder.for_objective(objective),
      "",
      "Feedback intent: #{feedback.feedback_kind.tr("_", " ")}",
      "User feedback:",
      feedback.content.to_s.strip
    ]

    anchor_lines = []
    anchor_lines += brief["success_criteria"].map { |c| "- Success criterion: #{c}" }
    anchor_lines += brief["constraints"].map { |c| "- Constraint: #{c}" }
    anchor_lines << "- Deliverable: #{brief["deliverable"]}" if brief["deliverable"].present?

    if anchor_lines.any?
      lines << ""
      lines << "ORIGINAL OBJECTIVE ANCHORS (use these as strongly weighted priorities when generating next-step tasks — do not reject tasks that explore adjacent areas, but prefer tasks that advance these criteria):"
      lines.concat(anchor_lines)
    end

    if feedback.task.present?
      lines << ""
      lines << "The feedback references this task:"
      lines << "- #{feedback.task.description}"
      lines << "  Result: #{feedback.task.result_summary}" if feedback.task.result_summary.present?
    end

    if feedback.research_snapshot.present?
      lines << ""
      lines << "The feedback references this research finding:"
      lines << "- #{feedback.research_snapshot.key}: #{feedback.research_snapshot.value}"
      if feedback.research_snapshot.delta_note.present?
        lines << "  Change note: #{feedback.research_snapshot.delta_note}"
      end
    end

    completed_tasks = objective.tasks.where(status: "completed").order(updated_at: :desc).limit(8)
    if completed_tasks.any?
      lines << ""
      lines << "Recently completed tasks:"
      completed_tasks.each do |task|
        lines << "- #{task.description}"
        lines << "  Result: #{task.result_summary}" if task.result_summary.present?
      end
    end

    snapshots = objective.research_snapshots.recent_first.limit(10)
    if snapshots.any?
      lines << ""
      lines << "Current research findings:"
      snapshots.each do |snapshot|
        line = "- #{snapshot.key}: #{snapshot.value}"
        line += " (#{snapshot.delta_note})" if snapshot.delta_note.present?
        lines << line
      end
    end

    rated_feedback = objective.research_snapshot_feedbacks.includes(:research_snapshot).recent_first.limit(8)
    if rated_feedback.any?
      positives = rated_feedback.select { |entry| entry.rating == "good" }
      negatives = rated_feedback.select { |entry| entry.rating == "bad" }

      if positives.any?
        lines << ""
        lines << "Positively rated findings to preserve or build on:"
        positives.each do |entry|
          lines << format_rated_finding(entry)
        end
      end

      if negatives.any?
        lines << ""
        lines << "Negatively rated findings to avoid or re-check:"
        negatives.each do |entry|
          lines << format_rated_finding(entry)
        end
      end
    end

    lines.join("\n")
  end

  def format_rated_finding(entry)
    snapshot = entry.research_snapshot
    line = "- #{snapshot.key}: #{snapshot.value}"
    line += " [reason: #{entry.reason}]" if entry.reason.present?
    line
  end
end
