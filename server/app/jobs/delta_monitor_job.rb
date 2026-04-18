class DeltaMonitorJob < ApplicationJob
  queue_as :background

  MAX_SNAPSHOTS = 20
  ALERT_TTL = 24.hours
  MAX_AGE = 2.hours

  def perform
    channel_id = ENV.fetch("SLACK_FEED_CHANNEL_IDS", "").split(",").map(&:strip).first.presence
    return unless channel_id

    recent_changed_snapshots.find_each do |snapshot|
      next if alerted?(snapshot)

      Slack::Notifier.call(
        channel: channel_id,
        text: format_snapshot(snapshot),
        workspace: snapshot.objective.workspace
      )
      mark_alerted(snapshot)
    rescue => e
      Rails.logger.warn("[DeltaMonitorJob] Failed to notify for snapshot #{snapshot.id}: #{e.message}")
    end
  end

  private

  def recent_changed_snapshots
    ResearchSnapshot
      .includes(objective: :workspace)
      .where.not(delta_note: [nil, ""])
      .where("checked_at >= ?", MAX_AGE.ago)
      .order(checked_at: :desc)
      .limit(MAX_SNAPSHOTS)
  end

  def alerted?(snapshot)
    Rails.cache.exist?(alert_cache_key(snapshot))
  end

  def mark_alerted(snapshot)
    Rails.cache.write(alert_cache_key(snapshot), true, expires_in: ALERT_TTL)
  end

  def alert_cache_key(snapshot)
    "delta_monitor:#{snapshot.id}:#{snapshot.updated_at.to_i}"
  end

  def format_snapshot(snapshot)
    objective_label = snapshot.objective.goal.to_s.truncate(100)
    detail = snapshot.delta_note.presence || snapshot.value.to_s.truncate(280)
    [
      "Research delta for objective: #{objective_label}",
      detail
    ].join("\n")
  end
end
