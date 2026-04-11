class ObjectiveFeedbackCompletionSummaryBuilder
  def call(feedback)
    tasks = feedback.follow_up_tasks.where(status: "completed").order(:created_at).to_a
    return nil if tasks.empty?

    snapshots = feedback.objective.research_snapshots.where(task_id: tasks.map(&:id)).recent_first.limit(3)
    updates = snapshots.map do |snapshot|
      if snapshot.delta_note.present?
        "#{snapshot.key}: #{snapshot.delta_note}"
      else
        "#{snapshot.key}: #{snapshot.value}"
      end
    end

    intro = "From your #{feedback.feedback_kind.tr('_', ' ')} request, AgentKVT completed #{tasks.count} follow-up task#{"s" unless tasks.count == 1}."

    if updates.any?
      "#{intro} What changed: #{updates.join('; ')}".truncate(420)
    else
      findings = tasks.filter_map(&:result_summary).map(&:strip).reject(&:blank?).uniq.first(2)
      return intro if findings.empty?

      "#{intro} New findings: #{findings.join(' ')}".truncate(420)
    end
  end
end
