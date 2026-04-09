class ObjectiveComposer
  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are AgentKVT's guided objective composer.
    Your job is to turn a rough user request into a planning-ready objective brief for a private local-first agent system.

    Respond with ONLY valid JSON using this exact structure:
    {
      "assistant_message": "string",
      "suggested_goal": "string",
      "brief_json": {
        "context": ["string"],
        "success_criteria": ["string"],
        "constraints": ["string"],
        "preferences": ["string"],
        "deliverable": "string",
        "open_questions": ["string"]
      },
      "missing_fields": ["context", "success_criteria", "constraints", "preferences", "deliverable", "open_questions"],
      "ready_to_finalize": true
    }

    Rules:
    - Keep assistant_message concise and conversational.
    - Ask at most 2 high-value follow-up questions in assistant_message.
    - Keep suggested_goal to one sentence.
    - Only mark ready_to_finalize true when the brief contains enough detail to produce better task planning than a raw one-line request.
    - If information is still missing, keep it out of brief_json and list it in missing_fields.
    - Preserve useful existing brief details instead of deleting them.
    - Do not use markdown fences or prose outside the JSON object.
  PROMPT

  FALLBACK_MODEL = ENV.fetch("OBJECTIVE_COMPOSER_MODEL", ENV.fetch("OLLAMA_MODEL", OllamaClient::DEFAULT_MODEL)).freeze

  def initialize(client: OllamaClient.new, model: FALLBACK_MODEL)
    @client = client
    @model = model
  end

  def call(draft)
    raw = @client.chat(
      messages: build_messages(draft),
      model: @model,
      format: "json"
    )

    normalize_response(draft, JSON.parse(raw))
  rescue JSON::ParserError, RuntimeError => e
    Rails.logger.error("[ObjectiveComposer] objective_draft=#{draft.id} error=#{e.message}")
    fallback_turn(draft)
  end

  private

  def build_messages(draft)
    [
      { role: "system", content: SYSTEM_PROMPT },
      { role: "system", content: draft_context(draft) }
    ] + draft.objective_draft_messages.chronological.map do |message|
      { role: message.role, content: message.content }
    end
  end

  def draft_context(draft)
    <<~TEXT
      Template key: #{draft.template_key}
      Template title: #{ObjectiveComposerTemplates.title_for(draft.template_key)}
      Template guidance: #{ObjectiveComposerTemplates.guidance_for(draft.template_key)}
      Required fields before ready_to_finalize can be true: #{ObjectiveComposerTemplates.required_fields_for(draft.template_key).join(", ")}

      Current planning summary:
      #{ObjectivePlanningInputBuilder.for_draft(draft, goal: draft.suggested_goal).presence || "(No saved brief yet)"}
    TEXT
  end

  def normalize_response(draft, parsed)
    brief = ObjectivePlanningInputBuilder.normalize_brief(parsed["brief_json"])
    missing_fields = normalize_missing_fields(parsed["missing_fields"], brief, draft.template_key)
    suggested_goal = parsed["suggested_goal"].to_s.strip.presence || fallback_goal(draft, brief)
    assistant_message = parsed["assistant_message"].to_s.strip.presence || fallback_assistant_message(draft, brief)

    ready_to_finalize =
      missing_fields.empty? &&
      suggested_goal.present? &&
      (
        boolean_value(parsed["ready_to_finalize"]) ||
        ObjectivePlanningInputBuilder.filled_fields_count(brief) >= 3
      )

    {
      "assistant_message" => assistant_message,
      "suggested_goal" => suggested_goal,
      "brief_json" => brief,
      "missing_fields" => missing_fields,
      "ready_to_finalize" => ready_to_finalize
    }
  end

  def normalize_missing_fields(raw_missing_fields, brief, template_key)
    requested = Array(raw_missing_fields)
      .map(&:to_s)
      .map(&:strip)
      .select { |field| ObjectiveComposerTemplates::FIELD_KEYS.include?(field) }

    (requested + ObjectivePlanningInputBuilder.missing_fields(brief, template_key)).uniq
  end

  def fallback_turn(draft)
    brief = fallback_brief(draft)
    missing_fields = ObjectivePlanningInputBuilder.missing_fields(brief, draft.template_key)
    suggested_goal = fallback_goal(draft, brief)

    {
      "assistant_message" => fallback_assistant_message(draft, brief),
      "suggested_goal" => suggested_goal,
      "brief_json" => brief,
      "missing_fields" => missing_fields,
      "ready_to_finalize" => (
        missing_fields.empty? &&
        ObjectivePlanningInputBuilder.filled_fields_count(brief) >= 3 &&
        suggested_goal.present?
      )
    }
  end

  def fallback_brief(draft)
    brief = ObjectivePlanningInputBuilder.normalize_brief(draft.brief_json)
    last_user_message = draft.objective_draft_messages.where(role: "user").chronological.last&.content.to_s.strip
    if last_user_message.present? && !brief["context"].include?(last_user_message)
      brief["context"] = (brief["context"] + [last_user_message]).uniq
    end
    brief
  end

  def fallback_goal(draft, brief)
    draft.suggested_goal.to_s.strip.presence ||
      brief["context"].first.presence ||
      draft.objective_draft_messages.where(role: "user").chronological.last&.content.to_s.strip.presence ||
      "#{ObjectiveComposerTemplates.title_for(draft.template_key)} plan"
  end

  def fallback_assistant_message(draft, brief)
    missing_fields = ObjectivePlanningInputBuilder.missing_fields(brief, draft.template_key)
    if draft.objective_draft_messages.empty?
      return initial_prompt_for(draft.template_key)
    end

    if missing_fields.any?
      field_list = missing_fields.first(2).map { |field| ObjectivePlanningInputBuilder.humanize_field(field).downcase }.join(" and ")
      "I have the outline. What should I know about #{field_list}?"
    else
      "This looks planning-ready. Review the goal and create the objective when it matches what you want."
    end
  end

  def initial_prompt_for(template_key)
    case ObjectiveComposerTemplates.normalize_template_key(template_key)
    when "budget"
      "What kind of budget do you want help with, and what outcome or deadline matters most?"
    when "date_night"
      "What kind of date night are you hoping for, and what budget, timing, or location constraints should I respect?"
    when "trip_planning"
      "Where are you planning to go, who is traveling, and what dates or budget constraints matter most?"
    when "household_planning"
      "What household project or responsibility are you trying to plan, and what deadline or constraints should I optimize for?"
    else
      "What are you trying to accomplish, and what would make the result feel successful?"
    end
  end

  def boolean_value(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end
end
