module V1
  module Agent
    class AgentLogsController < BaseController
      def create
        agent_log = current_workspace.agent_logs.create!(agent_log_params)

        render json: { agent_log: serialize_agent_log(agent_log) }, status: :created
      end

      private

      def agent_log_params
        params.require(:agent_log).permit(
          :phase,
          :content,
          :timestamp,
          metadata_json: {}
        )
      end
    end
  end
end
