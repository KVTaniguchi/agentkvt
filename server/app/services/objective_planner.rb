require "set"

class ObjectivePlanner
  MAX_TASKS = 12
  GENERIC_DESCRIPTION_PATTERNS = [
    /\Aclarify objective scope, assumptions, and success criteria/i,
    /\Aresearch and compare the top options relevant to this objective/i,
    /\Aidentify constraints, risks, costs, and dependencies/i,
    /\Apropose a recommended approach with rationale/i,
    /\Acreate an execution checklist with milestones and deadlines/i,
    /\Alist open questions and the next information to gather/i,
    /\Acontinue the research for this objective/i
  ].freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are AgentKVT's Task Orchestrator. Given a goal, output a JSON array of executable task contracts.
    Return enough tasks to fully satisfy the objective:
    - Simple goals: at least 4 tasks
    - Multi-part or high-uncertainty goals: 6-10 tasks
    Each element must be an object with:
    - "description" (required): concise execution-oriented task string
    - "task_kind" (optional): one of "research", "action", or "synthesis"
    - "allowed_tool_ids" (optional): array of the narrowest tool ids the task should use
    - "required_capabilities" (optional): array of agent capabilities needed to run the task
    - "done_when" (optional): one sentence completion condition
    Respond with ONLY valid JSON — no markdown fences, no prose, no explanation.

    SPECIALIST BREAKDOWN: For multi-part goals, assign distinct domain roles rather than generic "research X" tasks.
    Examples of good specialist splits:
    - Trip planning → Timing/Crowds Specialist, Logistics Coordinator, Budget Auditor, Dining/Experience Researcher
    - Product comparison → Feature Analyst, Pricing Auditor, User Reviews Specialist, Compatibility Checker
    - Event planning → Venue Researcher, Catering/Food Specialist, Cost Auditor, Scheduling Coordinator
    - Shopping → Product Researcher, Price Auditor, Stock Checker, Cart/Checkout Coordinator

    TASK KIND RULES:
    - "research" = gather or verify facts.
    - "action" = take an external step with tools like site_scout, send_notification_email, write_reminder, or read_calendar.
    - "synthesis" = consolidate findings into a recommendation, working brief, or final closeout.
    - Prefer "research" unless the task clearly requires taking an outside action or summarizing a completed body of work.

    SEARCH GROUNDING: Each task description must embed a specific directive, not a vague mandate.
    BAD: "Research Epic Universe theme park"
    GOOD: "Search for 'Epic Universe 2026 crowd calendar' and extract per-land recommended visit durations and average wait times for headliner rides. Flag any estimate under 3 hours per land as suspicious."
    GOOD: "Use the `site_scout` tool to navigate to Target.com, search for '16x25x1 HVAC filter', and extract the availability and price for the 3-pack. If available for pickup, add it to the cart and confirm the cart subtotal."

    SOURCE TARGETING: Distinguish information type when choosing sources.
    - Official/brand sites (universalorlando.com, disney.com, ikea.com, delta.com, etc.): use for factual data — prices, hours, availability, policies, official maps.
    - Expert/community sources (touringplans.com, orlandoinformer.com, magicguides.com, wirecutter.com, rtings.com, reddit.com, niche review blogs): use for strategy, wait times, crowd patterns, real-world performance, and comparative analysis.
    When a task requires strategic insight (crowd levels, best visit times, which option wins in practice), target expert sources explicitly — do not just say "search for X".
    BAD: "Search for Epic Universe crowd levels in July"
    GOOD: "Search touringplans.com or orlandoinformer.com for 2026 Epic Universe crowd calendar for July — extract expected wait times for headliner rides and per-land recommended visit durations."

    CONSTRAINT EMBEDDING: When constraints or preferences are provided in the goal, embed them as explicit conditions inside each relevant task description. Do not treat constraints as ambient context — repeat them as thresholds within the task.
    BAD: "Research Epic Universe headliner ride wait times"
    GOOD: "Search orlandoinformer.com for Epic Universe headliner wait times in July peak season. Assume 60-90+ minute waits for Dark Universe and Ministry of Magic. Flag any itinerary plan allocating less than 3 hours to either land as unrealistic given these crowd levels."
    For budget constraints: include the cap in each pricing task. For date/season constraints: include the crowd assumptions in each scheduling or timing task.

    ACTION TASK RULES:
    - If a task involves adding to cart, booking, sending an email, creating a reminder, scheduling, or filling a web form, mark it "action".
    - Action tasks should name the narrowest allowed tools, for example ["site_scout"] or ["send_notification_email"].

    REJECTION CRITERIA: Include explicit minimum thresholds or sanity checks in task descriptions when relevant (e.g. minimum group size, minimum time blocks, budget caps).

    CRITIC TASK: For objectives with 6+ tasks, always add a final validation task as the last element.
    The critic task should read all prior findings and flag: unrealistic estimates, missing constraints, budget overruns, or logistical impossibilities.
    Example critic task: "Review all draft findings for this objective. Flag any time estimate that seems too short for a group, any cost that exceeds stated budget, or any logistical gap (travel time, reservations needed, capacity limits)." This should usually be "synthesis".

    Example output: [{"description":"Search for hotel options near the convention center with prices and availability for the target dates","task_kind":"research","allowed_tool_ids":["multi_step_search"],"done_when":"At least one snapshot captures current prices, dates, and cancellation policy details."},{"description":"Use the site_scout tool to add the best in-stock 16x25x1 HVAC filter 3-pack to the Target cart and confirm the subtotal.","task_kind":"action","allowed_tool_ids":["site_scout"],"required_capabilities":["objective_research","site_scout"],"done_when":"An objective snapshot records the cart subtotal or the blocker preventing checkout."},{"description":"Review all findings and produce the recommended next move with risks and immediate action items.","task_kind":"synthesis","done_when":"A final objective snapshot captures the recommendation and marks the task complete."}]
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
      task: "objective-planner",
      options: { num_ctx: 8192, think: false }
    )

    task_defs = normalize_task_defs(JSON.parse(raw))
    llm_task_defs = dedupe_task_defs(task_defs.filter_map { |task_def| normalize_task_def(task_def) })
    llm_task_defs = replace_generic_task_defs(objective, llm_task_defs)

    if llm_task_defs.length < min_task_count
      llm_task_defs += supplemental_task_defs(
        objective: objective,
        existing: llm_task_defs,
        needed: (min_task_count - llm_task_defs.length)
      )
    end

    created = persist_tasks(objective, llm_task_defs.first(MAX_TASKS))

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
    return [] if objective.goal.to_s.strip.empty?

    heuristic_task_defs(objective, min_task_count: min_task_count).filter_map do |attrs|
      next if attrs[:description].blank?
      objective.tasks.create!(attrs.merge(status: "proposed"))
    end
  end

  def persist_tasks(objective, task_defs)
    task_defs.filter_map do |task_def|
      next if task_def[:description].blank?
      objective.tasks.create!(task_def.merge(description: task_def[:description].truncate(500), status: "proposed"))
    end
  end

  # Splits multi-sentence goals into separate tasks, then tops up with a structured checklist.
  def heuristic_descriptions(objective, min_task_count:)
    goal = objective.goal.to_s.strip
    brief = ObjectivePlanningInputBuilder.normalize_brief(objective.brief_json)
    context_entries = brief["context"].presence || [goal]
    success_criteria = brief["success_criteria"].first(2)
    constraints = brief["constraints"].first(2)
    preferences = brief["preferences"].first(2)
    open_questions = brief["open_questions"].first(2)
    deliverable = brief["deliverable"].to_s.strip
    anchor = context_entries.join(" ").truncate(220)

    tasks = [
      "Identify the strongest viable options or facts for: #{anchor}. Capture concrete prices, dates, limits, or availability."
    ]

    if constraints.any?
      tasks << "Validate the leading options against these hard constraints: #{constraints.join('; ')}. Flag anything that fails."
    end

    if success_criteria.any?
      tasks << "Score the strongest options against these success criteria: #{success_criteria.join('; ')}."
    end

    if preferences.any?
      tasks << "Compare the tradeoffs that matter most for this objective: #{preferences.join('; ')}."
    end

    if deliverable.present?
      tasks << "Draft the requested deliverable: #{deliverable.truncate(220)}. Include a recommended next move and backup option."
    else
      tasks << "Draft a concrete recommendation for this objective, including the best option, why it wins, and what to do next."
    end

    if open_questions.any?
      tasks << "Answer these open questions if they would materially change the recommendation: #{open_questions.join('; ')}."
    end

    tasks << "Stress-test the best recommendation for hidden costs, timing issues, reservations, or missing dependencies."
    tasks << "List the one unanswered question that would most change the recommendation, if any still remain."

    tasks.map(&:strip).reject(&:blank?).uniq.first([min_task_count, MAX_TASKS].max)
  end

  def heuristic_task_defs(objective, min_task_count:)
    heuristic_descriptions(objective, min_task_count: min_task_count).map do |description|
      normalize_task_def({ "description" => description })
    end.compact
  end

  def supplemental_task_defs(objective:, existing:, needed:)
    return [] if needed <= 0
    heuristic_task_defs(objective, min_task_count: needed + existing.length)
      .reject { |task_def| existing.any? { |existing_def| existing_def[:description].casecmp?(task_def[:description]) } }
      .first(needed)
  end

  def replace_generic_task_defs(objective, task_defs)
    return task_defs if task_defs.empty?

    replacements = heuristic_task_defs(
      objective,
      min_task_count: [task_defs.length, minimum_task_count(objective.goal)].max
    )
    replacement_index = 0
    seen = task_defs.each_with_object(Set.new) { |task_def, acc| acc << task_def[:description].downcase }

    task_defs.filter_map do |task_def|
      next task_def unless generic_description?(task_def[:description])

      replacement = nil
      while replacement.nil? && replacement_index < replacements.length
        candidate = replacements[replacement_index]
        replacement_index += 1
        next if seen.include?(candidate[:description].downcase)

        seen << candidate[:description].downcase
        replacement = candidate
      end

      replacement || task_def
    end
  end

  def normalize_task_def(task_def)
    case task_def
    when String
      description = task_def.to_s.strip
      return if description.empty?

      Task.execution_contract(description: description).merge(description: description)
    when Hash
      description = task_def["description"].to_s.strip
      return if description.empty?

      Task.execution_contract(
        description: description,
        task_kind: task_def["task_kind"],
        allowed_tool_ids: task_def["allowed_tool_ids"],
        required_capabilities: task_def["required_capabilities"],
        done_when: task_def["done_when"]
      ).merge(description: description)
    end
  end

  def dedupe_task_defs(task_defs)
    seen = Set.new
    task_defs.filter do |task_def|
      seen.add?(task_def[:description].downcase)
    end
  end

  def generic_description?(description)
    GENERIC_DESCRIPTION_PATTERNS.any? { |pattern| pattern.match?(description.to_s.strip) }
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
