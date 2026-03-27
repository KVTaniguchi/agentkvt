module V1
  class BootstrapController < BaseController
    def show
      family_members = current_workspace.family_members.order(:display_name)
      missions = current_workspace.missions.recent_first.limit(50)

      render json: {
        workspace: serialize_workspace(current_workspace),
        family_members: family_members.map { |member| serialize_family_member(member) },
        missions: missions.map { |mission| serialize_mission(mission) },
        pending_action_items_count: current_workspace.action_items.where(is_handled: false).count,
        recent_agent_log_count: current_workspace.agent_logs.where("timestamp >= ?", 24.hours.ago).count,
        server_time: Time.current.iso8601
      }
    end
  end
end
