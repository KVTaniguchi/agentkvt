require "base64"

module ApiSerialization
  extend ActiveSupport::Concern

  private

  def serialize_workspace(workspace)
    {
      id: workspace.id,
      name: workspace.name,
      slug: workspace.slug,
      server_mode: workspace.server_mode,
      agent_email: workspace.agent_identity&.from_email,
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

  def serialize_chat_thread(thread)
    latest_message =
      if thread.association(:chat_messages).loaded?
        thread.chat_messages.max_by(&:timestamp)
      else
        thread.chat_messages.order(timestamp: :desc).first
      end

    pending_message_count =
      if thread.association(:chat_messages).loaded?
        thread.chat_messages.count do |message|
          message.role == "user" && %w[pending processing].include?(message.status)
        end
      else
        thread.chat_messages.where(role: "user", status: %w[pending processing]).count
      end

    message_count =
      if thread.association(:chat_messages).loaded?
        thread.chat_messages.length
      else
        thread.chat_messages.count
      end

    {
      id: thread.id,
      workspace_id: thread.workspace_id,
      created_by_profile_id: thread.created_by_profile_id,
      title: thread.title,
      system_prompt: thread.system_prompt,
      allowed_tool_ids: thread.allowed_tool_ids,
      latest_message_preview: latest_message&.content&.truncate(140),
      latest_message_role: latest_message&.role,
      latest_message_status: latest_message&.status,
      latest_message_at: iso8601(latest_message&.timestamp),
      pending_message_count: pending_message_count,
      message_count: message_count,
      created_at: iso8601(thread.created_at),
      updated_at: iso8601(thread.updated_at)
    }
  end

  def serialize_chat_message(message)
    {
      id: message.id,
      chat_thread_id: message.chat_thread_id,
      role: message.role,
      content: message.content,
      status: message.status,
      error_message: message.error_message,
      timestamp: iso8601(message.timestamp),
      author_profile_id: message.author_profile_id,
      created_at: iso8601(message.created_at),
      updated_at: iso8601(message.updated_at)
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

  def serialize_objective_draft_message(message)
    {
      id: message.id,
      objective_draft_id: message.objective_draft_id,
      role: message.role,
      content: message.content,
      timestamp: iso8601(message.timestamp),
      created_at: iso8601(message.created_at),
      updated_at: iso8601(message.updated_at)
    }
  end

  def serialize_objective_draft(draft)
    {
      id: draft.id,
      workspace_id: draft.workspace_id,
      created_by_profile_id: draft.created_by_profile_id,
      finalized_objective_id: draft.finalized_objective_id,
      status: draft.status,
      template_key: draft.template_key,
      brief_json: ObjectivePlanningInputBuilder.normalize_brief(draft.brief_json),
      suggested_goal: draft.suggested_goal,
      assistant_message: draft.assistant_message,
      missing_fields: draft.missing_fields,
      ready_to_finalize: draft.ready_to_finalize,
      planner_summary: draft.planner_summary,
      messages: draft.objective_draft_messages.chronological.map { |message| serialize_objective_draft_message(message) },
      created_at: iso8601(draft.created_at),
      updated_at: iso8601(draft.updated_at)
    }
  end

  def serialize_objective(objective)
    inbound_file_ids =
      if objective.association(:inbound_files).loaded?
        objective.inbound_files.map(&:id)
      else
        objective.inbound_file_ids
      end

    {
      id: objective.id,
      workspace_id: objective.workspace_id,
      goal: objective.goal,
      status: objective.status,
      priority: objective.priority,
      brief_json: ObjectivePlanningInputBuilder.normalize_brief(objective.brief_json),
      objective_kind: objective.objective_kind,
      creation_source: objective.creation_source,
      planner_summary: ObjectivePlanningInputBuilder.for_objective(objective),
      hands_config: objective.hands_config || {},
      inbound_file_ids: inbound_file_ids,
      in_progress_task_count: objective.tasks.count { |t| t.status == "in_progress" },
      snapshot_count: objective.research_snapshots.size,
      created_at: iso8601(objective.created_at),
      updated_at: iso8601(objective.updated_at)
    }
  end

  def serialize_task(task)
    {
      id: task.id,
      objective_id: task.objective_id,
      source_feedback_id: task.source_feedback_id,
      description: task.description,
      task_kind: task.task_kind,
      allowed_tool_ids: task.allowed_tool_ids,
      required_capabilities: task.required_capabilities,
      done_when: task.done_when,
      status: task.status,
      result_summary: task.result_summary,
      created_at: iso8601(task.created_at),
      updated_at: iso8601(task.updated_at)
    }
  end

  def serialize_objective_feedback(feedback)
    {
      id: feedback.id,
      objective_id: feedback.objective_id,
      task_id: feedback.task_id,
      research_snapshot_id: feedback.research_snapshot_id,
      role: feedback.role,
      feedback_kind: feedback.feedback_kind,
      status: feedback.status,
      content: feedback.content,
      completion_summary: feedback.completion_summary,
      completed_at: iso8601(feedback.completed_at),
      created_at: iso8601(feedback.created_at),
      updated_at: iso8601(feedback.updated_at)
    }
  end

  def serialize_objective_feedback_mutation(feedback)
    {
      objective: serialize_objective(feedback.objective.reload),
      objective_feedback: serialize_objective_feedback(feedback.reload),
      follow_up_tasks: feedback.follow_up_tasks.order(:created_at).map { |task| serialize_task(task) }
    }
  end

  def serialize_research_snapshot_feedback(feedback)
    {
      id: feedback.id,
      workspace_id: feedback.workspace_id,
      objective_id: feedback.objective_id,
      research_snapshot_id: feedback.research_snapshot_id,
      created_by_profile_id: feedback.created_by_profile_id,
      role: feedback.role,
      rating: feedback.rating,
      reason: feedback.reason,
      created_at: iso8601(feedback.created_at),
      updated_at: iso8601(feedback.updated_at)
    }
  end

  def serialize_research_snapshot(snapshot)
    viewer_feedback = viewer_feedback_for(snapshot)
    {
      id: snapshot.id,
      objective_id: snapshot.objective_id,
      task_id: snapshot.task_id,
      key: snapshot.key,
      value: snapshot.value,
      previous_value: snapshot.previous_value,
      delta_note: snapshot.delta_note,
      is_repellent: snapshot.is_repellent,
      repellent_reason: snapshot.repellent_reason,
      repellent_scope: snapshot.repellent_scope,
      snapshot_kind: snapshot.snapshot_kind,
      viewer_feedback_id: viewer_feedback&.id,
      viewer_feedback_rating: viewer_feedback&.rating,
      viewer_feedback_reason: viewer_feedback&.reason,
      good_feedback_count: snapshot.feedback_entries.where(rating: "good").count,
      bad_feedback_count: snapshot.feedback_entries.where(rating: "bad").count,
      checked_at: iso8601(snapshot.checked_at),
      created_at: iso8601(snapshot.created_at),
      updated_at: iso8601(snapshot.updated_at)
    }
  end

  def serialize_inbound_file(inbound_file, include_data: false)
    payload = {
      id: inbound_file.id,
      workspace_id: inbound_file.workspace_id,
      uploaded_by_profile_id: inbound_file.uploaded_by_profile_id,
      file_name: inbound_file.file_name,
      content_type: inbound_file.content_type,
      byte_size: inbound_file.byte_size,
      is_processed: inbound_file.is_processed,
      processed_at: iso8601(inbound_file.processed_at),
      timestamp: iso8601(inbound_file.timestamp),
      created_at: iso8601(inbound_file.created_at),
      updated_at: iso8601(inbound_file.updated_at)
    }
    payload[:file_base64] = Base64.strict_encode64(inbound_file.file_data) if include_data
    payload
  end

  def serialize_registration(reg)
    {
      id: reg.id,
      agent_id: reg.agent_id,
      capabilities: reg.capabilities,
      webhook_url: reg.webhook_url,
      status: reg.status,
      last_seen_at: iso8601(reg.last_seen_at)
    }
  end

  def iso8601(value)
    value&.iso8601
  end

  def current_viewer_profile_id
    raw_id = params[:viewer_profile_id].presence || params.dig(:research_snapshot_feedback, :created_by_profile_id).presence
    return nil if raw_id.blank?

    current_workspace.family_members.find_by(id: raw_id)&.id
  end

  def viewer_feedback_for(snapshot)
    viewer_profile_id = current_viewer_profile_id
    scope = snapshot.feedback_entries.where(role: "user")
    scope = scope.where(created_by_profile_id: viewer_profile_id) if viewer_profile_id.present?
    scope.order(updated_at: :desc).first
  end
end
