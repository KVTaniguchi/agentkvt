class PendingTasksDispatchJob < ApplicationJob
  queue_as :background

  def perform
    return unless AgentRegistration.online.exists?

    Task
      .where(status: "pending")
      .joins(objective: :workspace)
      .where(objectives: { status: "active" })
      .select(:id)
      .find_each do |task|
        TaskExecutorJob.perform_later(task.id.to_s)
      end
  end
end
