class StaleInProgressTasksJob < ApplicationJob
  queue_as :background

  STALE_THRESHOLD = 2.hours

  def perform
    stale_tasks = Task.where(status: "in_progress")
                      .where("claimed_at <= ?", STALE_THRESHOLD.ago)

    stale_tasks.find_each do |task|
      task.update_columns(status: "pending", claimed_at: nil, claimed_by_agent_id: nil)
      TaskExecutorJob.perform_later(task.id.to_s)
      Rails.logger.info("[StaleInProgressTasksJob] Reset and re-queued task #{task.id} (was claimed at #{task.claimed_at})")
    rescue => e
      Rails.logger.warn("[StaleInProgressTasksJob] Failed to reset task #{task.id}: #{e.message}")
    end
  end
end
