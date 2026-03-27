module V1
  module Agent
    class MissionLogsController < BaseController
      def create
        mission = current_workspace.missions.find(params[:mission_id] || params[:id])
        agent_log = current_workspace.agent_logs.create!(agent_log_params.merge(mission: mission))

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
