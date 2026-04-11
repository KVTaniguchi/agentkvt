class ObjectiveKickoff
  def call(objective)
    objective.update!(status: "active") unless objective.status == "active"

    if objective.tasks.empty?
      ObjectivePlannerJob.perform_later(objective.id.to_s)
      return
    end

    objective.tasks.where(status: "failed").find_each do |task|
      task.update!(status: "pending", result_summary: nil)
    end

    objective.tasks.where(status: "pending").find_each do |task|
      TaskExecutorJob.perform_later(task.id.to_s)
    end

    objective.objective_feedbacks.includes(:follow_up_tasks).find_each do |feedback|
      next if feedback.follow_up_tasks.empty?

      ObjectiveFeedbackLifecycle.new.refresh!(feedback)
    end
  end
end
