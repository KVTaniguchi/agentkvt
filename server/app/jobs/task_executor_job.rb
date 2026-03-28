class TaskExecutorJob < ApplicationJob
  queue_as :default

  # Marks the task in_progress and fires a webhook trigger to the Mac agent.
  # If the webhook fails, reverts status to pending so the next poll can retry.
  def perform(task_id)
    task = Task.find_by(id: task_id)
    return unless task
    return unless task.status == "pending"

    task.update!(status: "in_progress")

    triggered = MacAgentClient.new.trigger_task_search(task)

    unless triggered
      Rails.logger.warn("[TaskExecutorJob] Webhook delivery failed for task=#{task_id}, reverting to pending")
      task.update!(status: "pending")
    end
  end
end
