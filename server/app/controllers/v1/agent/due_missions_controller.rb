module V1
  module Agent
    class DueMissionsController < BaseController
      def index
        reference_time = parsed_time(params[:at]) || Time.current
        all_enabled = current_workspace.missions.enabled.recent_first
        due_missions = all_enabled.select do |mission|
          MissionSchedule.due?(mission, at: reference_time) || mission.run_requested_at.present?
        end

        render json: {
          checked_at: reference_time.iso8601,
          due_missions: due_missions.map { |mission| serialize_mission(mission) }
        }
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
