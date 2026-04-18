class TaskExecutorJob < ApplicationJob
  queue_as :default

  # Atomically claims a pending task using FOR UPDATE SKIP LOCKED so concurrent
  # workers cannot double-claim the same row. Routes to a capable registered agent
  # if one is online; otherwise falls back to the default webhook URL.
  # Reverts to pending if the webhook fails.
  def perform(task_id)
    task = nil
    agent = nil

    Task.transaction do
      task = Task.where(id: task_id, status: "pending")
                 .lock("FOR UPDATE SKIP LOCKED")
                 .first
      return unless task

      # Check for repelling snapshots (circuit breaker)
      repelling_snapshots = task.objective.research_snapshots.repelling
      if repelling_snapshots.exists?
        # Basic check: if the task description mentions any of the repellent scopes, bail out.
        task_desc_norm = task.description.downcase
        matched_repellent = repelling_snapshots.find do |rs|
          scope = rs.repellent_scope.to_s.downcase
          scope.present? && task_desc_norm.include?(scope)
        end
        
        if matched_repellent
          task.update_columns(
            status: "completed",
            result_summary: "Skipped due to known dead-end: #{matched_repellent.repellent_reason.presence || 'Circuit breaker triggered.'}"
          )
          return
        end
      end

      workspace = task.objective.workspace
      agent = AgentRegistration.capable_of(task.required_capabilities)
                               .where(workspace: workspace)
                               .order(last_seen_at: :desc)
                               .first

      task.update_columns(
        status: "in_progress",
        claimed_at: Time.current,
        claimed_by_agent_id: agent&.agent_id || "mac-agent"
      )
    end

    webhook_url = agent&.webhook_url
    effective_url = webhook_url.presence || MacAgentClient::DEFAULT_WEBHOOK_URL
    triggered = MacAgentClient.new(webhook_url: webhook_url).trigger_task_search(task)

    unless triggered
      Rails.logger.warn(
        "[TaskExecutorJob] Webhook delivery failed task=#{task_id} agent=#{agent&.agent_id || 'none'} url=#{effective_url} — reverting to pending"
      )
      task.update_columns(status: "pending", claimed_at: nil, claimed_by_agent_id: nil)
    end
  end
end
