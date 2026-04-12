class ObjectivePlanner
  MAX_TASKS = 12

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a specialist research task planner. Given a goal, output a JSON array of concrete research tasks.
    Return enough tasks to fully satisfy the objective:
    - Simple goals: at least 4 tasks
    - Multi-part or high-uncertainty goals: 6-10 tasks
    Each element must be an object with a single key "description" whose value is a concise action string.
    Respond with ONLY valid JSON — no markdown fences, no prose, no explanation.

    SPECIALIST BREAKDOWN: For multi-part goals, assign distinct domain roles rather than generic "research X" tasks.
    Examples of good specialist splits:
    - Trip planning → Timing/Crowds Specialist, Logistics Coordinator, Budget Auditor, Dining/Experience Researcher
    - Product comparison → Feature Analyst, Pricing Auditor, User Reviews Specialist, Compatibility Checker
    - Event planning → Venue Researcher, Catering/Food Specialist, Cost Auditor, Scheduling Coordinator

    SEARCH GROUNDING: Each task description must embed a specific directive, not a vague mandate.
    BAD: "Research Epic Universe theme park"
    GOOD: "Search for 'Epic Universe 2026 crowd calendar' and extract per-land recommended visit durations and average wait times for headliner rides. Flag any estimate under 3 hours per land as suspicious."

    REJECTION CRITERIA: Include explicit minimum thresholds or sanity checks in task descriptions when relevant (e.g. minimum group size, minimum time blocks, budget caps).

    CRITIC TASK: For objectives with 6+ tasks, always add a final validation task as the last element.
    The critic task should read all prior findings and flag: unrealistic estimates, missing constraints, budget overruns, or logistical impossibilities.
    Example critic task: "Review all draft findings for this objective. Flag any time estimate that seems too short for a group, any cost that exceeds stated budget, or any logistical gap (travel time, reservations needed, capacity limits)."

    Example output: [{"description":"Search for hotel options near the convention center with prices and availability for the target dates"},{"description":"Compare flight prices from PHL to SAN — extract cheapest options and latest same-day booking cutoffs"},{"description":"Review all findings: flag any hotel that exceeds the stated budget or any flight with less than 90 minutes connection time"}]
  PROMPT

  def initialize(client: OllamaClient.new)
    @client = client
  end

  # Prompts the LLM to decompose +objective.goal+ into reviewable Tasks and persists them.
  # Generated tasks start as `proposed`; the user must approve the plan before the
  # Mac agent begins executing them.
  def call(objective)
    goal = objective.goal.to_s.strip
    planning_input = ObjectivePlanningInputBuilder.for_objective(objective)
    min_task_count = minimum_task_count(planning_input.presence || goal)
    raw = nil
    raw = @client.chat(
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: planning_input.presence || objective.goal }
      ],
      format: "json",
      task: "objective-planner"
    )

    task_defs = normalize_task_defs(JSON.parse(raw))
    llm_descriptions = task_defs.filter_map do |t|
      next unless t.is_a?(Hash)
      description = t["description"].to_s.strip
      next if description.empty?
      description
    end.uniq

    if llm_descriptions.length < min_task_count
      llm_descriptions += supplemental_descriptions(
        goal: planning_input.presence || goal,
        existing: llm_descriptions,
        needed: (min_task_count - llm_descriptions.length)
      )
    end

    created = persist_tasks(objective, llm_descriptions.first(MAX_TASKS))

    return created if created.any?

    Rails.logger.warn("[ObjectivePlanner] objective=#{objective.id} LLM returned no usable tasks; using fallback")
    fallback_tasks(objective, min_task_count: min_task_count)
  rescue JSON::ParserError, RuntimeError => e
    Rails.logger.error("[ObjectivePlanner] objective=#{objective.id} error=#{e.message} raw=#{raw.inspect}")
    fallback_tasks(objective, min_task_count: min_task_count)
  end

  private

  def normalize_task_defs(parsed)
    return parsed if parsed.is_a?(Array)
    return parsed["tasks"] if parsed.is_a?(Hash) && parsed["tasks"].is_a?(Array)

    raise "Expected JSON array"
  end

  def fallback_tasks(objective, min_task_count:)
    goal = objective.goal.to_s.strip
    return [] if goal.empty?

    heuristic_descriptions(goal, min_task_count: min_task_count).filter_map do |description|
      next if description.blank?
      objective.tasks.create!(description: description, status: "proposed")
    end
  end

  def persist_tasks(objective, descriptions)
    descriptions.filter_map do |description|
      next if description.blank?
      objective.tasks.create!(description: description.truncate(500), status: "proposed")
    end
  end

  # Splits multi-sentence goals into separate tasks, then tops up with a structured checklist.
  def heuristic_descriptions(goal, min_task_count:)
    parts = goal.split(/(?<=[.!?])\s+|\n+/).map(&:strip).reject(&:empty?)
    seed = if parts.length >= 2 && parts.all? { |p| p.length >= 8 }
      parts.first(MAX_TASKS)
    else
      []
    end

    fallback = [
      "Clarify objective scope, assumptions, and success criteria for: #{goal.truncate(260)}",
      "Research and compare the top options relevant to this objective",
      "Identify constraints, risks, costs, and dependencies",
      "Propose a recommended approach with rationale",
      "Create an execution checklist with milestones and deadlines",
      "List open questions and the next information to gather"
    ]

    (seed + fallback).map(&:strip).reject(&:blank?).uniq.first([min_task_count, MAX_TASKS].max)
  end

  def supplemental_descriptions(goal:, existing:, needed:)
    return [] if needed <= 0
    heuristic_descriptions(goal, min_task_count: needed + existing.length)
      .reject { |desc| existing.include?(desc) }
      .first(needed)
  end

  def minimum_task_count(goal)
    return 4 if goal.blank?

    score = 0
    score += 1 if goal.length > 120
    score += 1 if goal.length > 260
    score += 1 if goal.scan(/[\n.;:]/).length >= 2
    score += 1 if goal.scan(/\b(and|or|then|while|plus|also|including|across)\b/i).length >= 2
    score += 1 if goal.scan(/\b(plan|compare|budget|timeline|itinerary|vendors|requirements|risks)\b/i).length >= 2

    case score
    when 0..1 then 4
    when 2..3 then 6
    else 8
    end
  end
end
