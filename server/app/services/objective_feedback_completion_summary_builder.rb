class ObjectiveFeedbackCompletionSummaryBuilder
  def call(feedback)
    tasks = feedback.follow_up_tasks.where(status: "completed").order(:created_at).to_a
    return nil if tasks.empty?

    tasks_by_id = tasks.index_by(&:id)
    snapshots = feedback.objective.research_snapshots.where(task_id: tasks.map(&:id)).recent_first.limit(3)
    updates = snapshots.filter_map do |snapshot|
      detail = snapshot.delta_note.presence || snapshot.value.presence
      next if detail.blank?

      "#{snapshot_label(snapshot, tasks_by_id: tasks_by_id)}: #{detail.to_s.squish}"
    end

    intro = "From your #{feedback.feedback_kind.tr('_', ' ')} request, AgentKVT completed #{tasks.count} follow-up task#{"s" unless tasks.count == 1}."

    if updates.any?
      [intro, "What changed:", *updates.map { |update| "- #{update}" }].join("\n")
    else
      findings = tasks.filter_map(&:result_summary).map(&:strip).reject(&:blank?).uniq.first(2)
      return intro if findings.empty?

      [intro, "New findings:", *findings.map { |finding| "- #{finding}" }].join("\n")
    end
  end

  private

  def snapshot_label(snapshot, tasks_by_id:)
    if task_summary_snapshot?(snapshot)
      tasks_by_id[snapshot.task_id]&.description.presence || humanize_key(snapshot.key)
    else
      humanize_key(snapshot.key)
    end
  end

  def task_summary_snapshot?(snapshot)
    normalized_key = snapshot.key.to_s.strip.downcase
    normalized_key.start_with?("task_summary_") || normalized_key.match?(/^task[\s_-]*summary[\s_-]*[0-9a-f]{4,}$/)
  end

  def humanize_key(key)
    cleaned = key.to_s.tr("_-", " ").squish
    cleaned.present? ? cleaned.sub(/\A./, &:upcase) : "Finding"
  end
end
