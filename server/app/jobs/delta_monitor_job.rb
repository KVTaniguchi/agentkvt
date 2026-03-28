class DeltaMonitorJob < ApplicationJob
  queue_as :background

  # Scans ResearchSnapshots written in the last 2 hours for meaningful deltas
  # and creates a deduplicated ActionItem in the owning workspace for each.
  def perform
    snapshots_with_delta = ResearchSnapshot
      .where.not(delta_note: nil)
      .where("checked_at >= ?", 2.hours.ago)
      .includes(objective: :workspace)

    snapshots_with_delta.each do |snapshot|
      workspace = snapshot.objective&.workspace
      next unless workspace

      # ActionItem.compute_hash deduplicates identical unhandled items
      payload = {
        "objective_id" => snapshot.objective_id,
        "task_id" => snapshot.task_id,
        "key" => snapshot.key,
        "previous_value" => snapshot.previous_value,
        "current_value" => snapshot.value,
        "delta_note" => snapshot.delta_note
      }.compact

      workspace.action_items.create!(
        title: "Research update: #{snapshot.key}",
        system_intent: "research.update",
        payload_json: payload,
        created_by: "delta_monitor"
      )
    rescue ActiveRecord::RecordNotUnique
      # Duplicate unhandled item — content_hash unique index prevented double-write
    end
  end
end
