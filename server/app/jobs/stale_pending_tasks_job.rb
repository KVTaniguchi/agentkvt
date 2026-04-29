class StalePendingTasksJob < ApplicationJob
  queue_as :background

  STALE_THRESHOLD = 10.minutes
  ALERT_TTL = 30.minutes

  def perform
    channel_id = ENV.fetch("SLACK_FEED_CHANNEL_IDS", "").split(",").map(&:strip).first.presence
    return unless channel_id

    stale_objectives.find_each do |objective|
      next if alerted?(objective)

      oldest_pending = objective.tasks.where(status: "pending").order(created_at: :asc).first
      next unless oldest_pending

      age_minutes = ((Time.current - oldest_pending.created_at) / 60).round
      pending_count = objective.tasks.where(status: "pending").count

      Slack::Notifier.call(
        channel: channel_id,
        text: ":hourglass: *Queue stalled* — \"#{objective.goal.truncate(80)}\" has #{pending_count} pending task(s) waiting #{age_minutes}m with no active workers.",
        workspace: objective.workspace
      )
      mark_alerted(objective)
    rescue => e
      Rails.logger.warn("[StalePendingTasksJob] Failed to notify for objective #{objective.id}: #{e.message}")
    end
  end

  private

  def stale_objectives
    Objective
      .includes(:workspace)
      .where(status: "active")
      .joins(:tasks)
      .where(tasks: { status: "pending" })
      .where("tasks.created_at <= ?", STALE_THRESHOLD.ago)
      .distinct
  end

  def alerted?(objective)
    Rails.cache.exist?(alert_cache_key(objective))
  end

  def mark_alerted(objective)
    Rails.cache.write(alert_cache_key(objective), true, expires_in: ALERT_TTL)
  end

  def alert_cache_key(objective)
    "stale_pending_tasks:#{objective.id}"
  end
end
