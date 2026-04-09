class ObjectivePlanningInputBuilder
  class << self
    def call(goal:, objective_kind: nil, brief_json: nil)
      normalized_goal = goal.to_s.strip
      normalized_kind = objective_kind.to_s.strip.presence
      brief = normalize_brief(brief_json)

      return normalized_goal if normalized_kind.blank? && !brief_present?(brief)

      lines = []
      lines << "Goal: #{normalized_goal}" if normalized_goal.present?
      lines << "Objective archetype: #{ObjectiveComposerTemplates.title_for(normalized_kind)}" if normalized_kind.present?

      append_list_section(lines, "Context", brief["context"])
      append_list_section(lines, "Success criteria", brief["success_criteria"])
      append_list_section(lines, "Constraints", brief["constraints"])
      append_list_section(lines, "Preferences", brief["preferences"])

      if brief["deliverable"].present?
        lines << "Deliverable:"
        lines << "- #{brief["deliverable"]}"
      end

      append_list_section(lines, "Open questions", brief["open_questions"])

      lines.join("\n").strip
    end

    def for_objective(objective)
      call(
        goal: objective.goal,
        objective_kind: objective.objective_kind,
        brief_json: objective.brief_json
      )
    end

    def for_draft(draft, goal: nil)
      call(
        goal: goal.presence || draft.suggested_goal,
        objective_kind: draft.template_key,
        brief_json: draft.brief_json
      )
    end

    def normalize_brief(raw_brief)
      source =
        case raw_brief
        when ActionController::Parameters then raw_brief.to_unsafe_h
        when Hash then raw_brief
        else {}
        end

      source = source.stringify_keys

      {
        "context" => normalize_list(source["context"]),
        "success_criteria" => normalize_list(source["success_criteria"]),
        "constraints" => normalize_list(source["constraints"]),
        "preferences" => normalize_list(source["preferences"]),
        "deliverable" => normalize_string(source["deliverable"]),
        "open_questions" => normalize_list(source["open_questions"])
      }
    end

    def brief_present?(brief)
      brief = normalize_brief(brief)
      FIELD_KEYS.any? { |field| field_present?(brief, field) }
    end

    def missing_fields(brief, objective_kind)
      normalized = normalize_brief(brief)
      ObjectiveComposerTemplates.required_fields_for(objective_kind).filter do |field|
        !field_present?(normalized, field)
      end
    end

    def filled_fields_count(brief)
      normalized = normalize_brief(brief)
      FIELD_KEYS.count { |field| field_present?(normalized, field) }
    end

    def field_present?(brief, field)
      value = normalize_brief(brief)[field.to_s]
      value.is_a?(Array) ? value.any? : value.present?
    end

    def humanize_field(field)
      field.to_s.tr("_", " ").capitalize
    end

    private

    FIELD_KEYS = ObjectiveComposerTemplates::FIELD_KEYS

    def normalize_list(value)
      Array(value)
        .flat_map { |entry| entry.is_a?(String) ? entry.split(/\r?\n/) : Array(entry) }
        .map { |entry| normalize_string(entry) }
        .compact
        .uniq
    end

    def normalize_string(value)
      value.to_s.strip.presence
    end

    def append_list_section(lines, title, entries)
      return if entries.blank?

      lines << "#{title}:"
      entries.each { |entry| lines << "- #{entry}" }
    end
  end
end
