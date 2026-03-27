module ApiSerialization
  extend ActiveSupport::Concern

  private

  def serialize_workspace(workspace)
    {
      id: workspace.id,
      name: workspace.name,
      slug: workspace.slug,
      server_mode: workspace.server_mode,
      created_at: iso8601(workspace.created_at),
      updated_at: iso8601(workspace.updated_at)
    }
  end

  def serialize_family_member(member)
    {
      id: member.id,
      workspace_id: member.workspace_id,
      device_id: member.device_id,
      display_name: member.display_name,
      symbol: member.symbol,
      source: member.source,
      created_at: iso8601(member.created_at),
      updated_at: iso8601(member.updated_at)
    }
  end

  def serialize_mission(mission)
    {
      id: mission.id,
      workspace_id: mission.workspace_id,
      owner_profile_id: mission.owner_profile_id,
      source_device_id: mission.source_device_id,
      mission_name: mission.mission_name,
      system_prompt: mission.system_prompt,
      trigger_schedule: mission.trigger_schedule,
      allowed_mcp_tools: mission.allowed_mcp_tools,
      is_enabled: mission.is_enabled,
      last_run_at: iso8601(mission.last_run_at),
      source_updated_at: iso8601(mission.source_updated_at),
      created_at: iso8601(mission.created_at),
      updated_at: iso8601(mission.updated_at)
    }
  end

  def serialize_action_item(action_item)
    {
      id: action_item.id,
      workspace_id: action_item.workspace_id,
      source_mission_id: action_item.source_mission_id,
      owner_profile_id: action_item.owner_profile_id,
      title: action_item.title,
      system_intent: action_item.system_intent,
      payload_json: action_item.payload_json,
      relevance_score: action_item.relevance_score,
      is_handled: action_item.is_handled,
      handled_at: iso8601(action_item.handled_at),
      timestamp: iso8601(action_item.timestamp),
      created_by: action_item.created_by,
      created_at: iso8601(action_item.created_at),
      updated_at: iso8601(action_item.updated_at)
    }
  end

  def serialize_agent_log(agent_log)
    {
      id: agent_log.id,
      workspace_id: agent_log.workspace_id,
      mission_id: agent_log.mission_id,
      mission_name: agent_log.mission&.mission_name,
      phase: agent_log.phase,
      content: agent_log.content,
      metadata_json: agent_log.metadata_json,
      tool_name: agent_log.metadata_json["tool_name"],
      timestamp: iso8601(agent_log.timestamp),
      created_at: iso8601(agent_log.created_at),
      updated_at: iso8601(agent_log.updated_at)
    }
  end

  def serialize_life_context_entry(entry)
    {
      id: entry.id,
      workspace_id: entry.workspace_id,
      key: entry.key,
      value: entry.value,
      created_at: iso8601(entry.created_at),
      updated_at: iso8601(entry.updated_at)
    }
  end

  def iso8601(value)
    value&.iso8601
  end
end
