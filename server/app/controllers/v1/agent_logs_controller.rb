module V1
  class AgentLogsController < BaseController
    def index
      logs = current_workspace.agent_logs

      if params[:phases].present?
        logs = logs.by_phases(params[:phases].split(",").map(&:strip))
      end

      if params[:since_minutes].present?
        minutes = params[:since_minutes].to_i
        logs = logs.since(minutes.minutes.ago) if minutes > 0
      end

      if params[:objective_id].present?
        logs = logs.by_objective(params[:objective_id])
      end

      if params[:task_id].present?
        logs = logs.by_task(params[:task_id])
      end

      if params[:tool_name].present?
        logs = logs.by_tool(params[:tool_name])
      end

      logs = logs.recent_first.limit(limit_param)
      render json: { agent_logs: logs.map { |log| serialize_agent_log(log) } }
    end

    def digest
      minutes = [(params[:since_minutes] || 120).to_i, 1].max
      since = minutes.minutes.ago
      logs = current_workspace.agent_logs.since(since)

      by_phase = logs.group(:phase).count

      # Recent errors/warnings — deduplicated by content, capped at 10
      error_entries = logs.by_phases(%w[error warning])
                         .recent_first
                         .limit(50)
                         .pluck(:phase, :content, :timestamp)
      grouped_errors = error_entries.group_by { |_phase, content, _ts| content.truncate(200) }
                                    .map do |content, entries|
        {
          phase: entries.first[0],
          content: content,
          count: entries.size,
          latest_at: entries.map { |e| e[2] }.max&.iso8601
        }
      end
      grouped_errors.sort_by! { |e| -e[:count] }
      grouped_errors = grouped_errors.first(10)

      # Active objectives — unique objective_ids seen in the window
      active_objective_ids = logs.where("metadata_json ->> 'objective_id' IS NOT NULL")
                                 .distinct
                                 .pluck(Arel.sql("metadata_json ->> 'objective_id'"))

      # Tool usage — count of tool_call entries per tool name
      tool_usage = logs.by_phases(%w[tool_call])
                       .where("metadata_json ->> 'tool_name' IS NOT NULL")
                       .group(Arel.sql("metadata_json ->> 'tool_name'"))
                       .count

      render json: {
        digest: {
          window_minutes: minutes,
          total_entries: by_phase.values.sum,
          by_phase: by_phase,
          errors: grouped_errors,
          active_objective_ids: active_objective_ids,
          tool_usage: tool_usage
        }
      }
    end

    private

    def limit_param
      requested = params[:limit].to_i
      return 100 if requested <= 0

      [requested, 500].min
    end
  end
end
