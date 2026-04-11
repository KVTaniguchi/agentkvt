class ObjectiveFeedbackLifecycle
  ACTIVE_TASK_STATUSES = %w[pending in_progress].freeze

  def initialize(summary_builder: ObjectiveFeedbackCompletionSummaryBuilder.new)
    @summary_builder = summary_builder
  end

  def refresh!(feedback)
    tasks = feedback.follow_up_tasks.order(:created_at).to_a
    return feedback if tasks.empty?

    next_status =
      if tasks.any? { |task| task.status == "proposed" }
        "review_required"
      elsif tasks.any? { |task| ACTIVE_TASK_STATUSES.include?(task.status) }
        feedback.objective.status == "active" ? "queued" : "planned"
      elsif tasks.all? { |task| task.status == "completed" }
        "completed"
      elsif tasks.any? { |task| task.status == "failed" }
        "failed"
      else
        feedback.status
      end

    attributes = { status: next_status }

    if next_status == "completed"
      attributes[:completed_at] = feedback.completed_at || Time.current
      attributes[:completion_summary] = @summary_builder.call(feedback)
    elsif %w[review_required planned queued received].include?(next_status)
      attributes[:completed_at] = nil
      attributes[:completion_summary] = nil
    end

    feedback.update!(attributes) if needs_update?(feedback, attributes)
    feedback
  end

  private

  def needs_update?(feedback, attributes)
    attributes.any? do |key, value|
      feedback.public_send(key) != value
    end
  end
end
