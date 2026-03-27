module V1
  class AgentLogsController < BaseController
    def index
      logs = current_workspace.agent_logs.recent_first.limit(limit_param)
      render json: { agent_logs: logs.map { |log| serialize_agent_log(log) } }
    end

    private

    def limit_param
      requested = params[:limit].to_i
      return 100 if requested <= 0

      [requested, 500].min
    end
  end
end
