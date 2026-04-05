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

  def serialize_action_item(action_item)
    {
      id: action_item.id,
      workspace_id: action_item.workspace_id,
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

  def serialize_objective(objective)
    {
      id: objective.id,
      workspace_id: objective.workspace_id,
      goal: objective.goal,
      status: objective.status,
      priority: objective.priority,
      created_at: iso8601(objective.created_at),
      updated_at: iso8601(objective.updated_at)
    }
  end

  def serialize_task(task)
    {
      id: task.id,
      objective_id: task.objective_id,
      description: task.description,
      status: task.status,
      result_summary: task.result_summary,
      created_at: iso8601(task.created_at),
      updated_at: iso8601(task.updated_at)
    }
  end

  def serialize_research_snapshot(snapshot)
    {
      id: snapshot.id,
      objective_id: snapshot.objective_id,
      task_id: snapshot.task_id,
      key: snapshot.key,
      value: snapshot.value,
      previous_value: snapshot.previous_value,
      delta_note: snapshot.delta_note,
      checked_at: iso8601(snapshot.checked_at),
      created_at: iso8601(snapshot.created_at),
      updated_at: iso8601(snapshot.updated_at)
    }
  end

  def iso8601(value)
    value&.iso8601
  end
end
