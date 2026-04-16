module V1
  class BootstrapsController < BaseController
    def show
      family_members = current_workspace.family_members.order(:display_name)
      agent_logs = current_workspace.agent_logs.recent_first.limit(150)
      life_context_entries = current_workspace.life_context_entries.order(:key)

      render json: {
        workspace: serialize_workspace(current_workspace),
        family_members: family_members.map { |member| serialize_family_member(member) },
        agent_logs: agent_logs.map { |log| serialize_agent_log(log) },
        life_context_entries: life_context_entries.map { |entry| serialize_life_context_entry(entry) },
        recent_agent_log_count: current_workspace.agent_logs.where("timestamp >= ?", 24.hours.ago).count,
        server_time: Time.current.iso8601
      }
    end
  end
end

