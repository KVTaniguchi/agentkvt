module V1
  module Agent
    class MissionLogsController < BaseController
      def index
        mission = current_workspace.missions.find(params[:mission_id])
        logs = mission.agent_logs.recent_first
        logs = logs.where(phase: phases_param) if phases_param.any?
        logs = logs.where("timestamp >= ?", since_minutes_param.minutes.ago) if params[:since_minutes].present?
        logs = logs.limit(limit_param)
        render json: { agent_logs: logs.map { |l| serialize_agent_log(l) } }
      end

      def create
        mission = current_workspace.missions.find(params[:mission_id] || params[:id])
        agent_log = current_workspace.agent_logs.create!(agent_log_params.merge(mission: mission))

        render json: { agent_log: serialize_agent_log(agent_log) }, status: :created
      end

      private

      def phases_param
        return [] unless params[:phases].present?
        params[:phases].to_s.split(",").map(&:strip).reject(&:empty?)
      end

      def since_minutes_param
        [ params[:since_minutes].to_i, 1 ].max
      end

      def limit_param
        requested = params[:limit].to_i
        return 100 if requested <= 0
        [ requested, 200 ].min
      end

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
