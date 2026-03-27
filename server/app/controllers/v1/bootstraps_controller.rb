module V1
  class BootstrapsController < BaseController
    def show
      family_members = current_workspace.family_members.order(:display_name)
      missions = current_workspace.missions.recent_first.limit(50)
      action_items = current_workspace.action_items.recent_first.limit(100)
      agent_logs = current_workspace.agent_logs.recent_first.limit(150)
      life_context_entries = current_workspace.life_context_entries.order(:key)

      render json: {
        workspace: serialize_workspace(current_workspace),
        family_members: family_members.map { |member| serialize_family_member(member) },
        missions: missions.map { |mission| serialize_mission(mission) },
        action_items: action_items.map { |item| serialize_action_item(item) },
        agent_logs: agent_logs.map { |log| serialize_agent_log(log) },
        life_context_entries: life_context_entries.map { |entry| serialize_life_context_entry(entry) },
        pending_action_items_count: current_workspace.action_items.where(is_handled: false).count,
        recent_agent_log_count: current_workspace.agent_logs.where("timestamp >= ?", 24.hours.ago).count,
        server_time: Time.current.iso8601
      }
    end
  end
end
