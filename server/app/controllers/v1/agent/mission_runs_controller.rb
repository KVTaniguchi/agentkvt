module V1
  module Agent
    class MissionRunsController < BaseController
      def create
        mission = current_workspace.missions.find(params[:mission_id] || params[:id])
        mission.update!(last_run_at: parsed_time(params[:ran_at]) || Time.current)

        render json: { mission: serialize_mission(mission) }
      end

      private

      def parsed_time(raw)
        return if raw.blank?

        Time.zone.parse(raw)
      rescue ArgumentError
        nil
      end
    end
  end
end
