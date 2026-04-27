module V1
  class ObjectiveDraftsController < BaseController
    def create
      prune_stale_drafts!

      draft = current_workspace.objective_drafts.create!(
        template_key: draft_create_params[:template_key],
        created_by_profile_id: draft_create_params[:created_by_profile_id]
      )

      if draft_create_params[:seed_text].present?
        draft.objective_draft_messages.create!(
          role: "user",
          content: draft_create_params[:seed_text]
        )
      end

      apply_composer_turn!(draft)

      render json: { objective_draft: serialize_objective_draft(draft.reload) }, status: :created
    end

    def show
      draft = find_draft!
      render json: { objective_draft: serialize_objective_draft(draft) }
    end

    def finalize
      draft = find_draft!
      normalized_brief = resolved_finalize_brief(draft)
      suggested_goal = finalize_params[:goal].to_s.strip.presence || draft.suggested_goal.to_s.strip.presence

      if suggested_goal.blank?
        return render json: { error: "Goal can't be blank" }, status: :unprocessable_entity
      end

      objective = nil

      ObjectiveDraft.transaction do
        objective = current_workspace.objectives.create!(
          goal: suggested_goal,
          status: finalize_params[:status].presence || "pending",
          priority: finalize_params.key?(:priority) ? finalize_params[:priority] : 0,
          brief_json: normalized_brief,
          objective_kind: draft.template_key,
          creation_source: "guided"
        )

        inbound_file_ids = Array(params.dig(:objective_draft, :inbound_file_ids)).compact
        if inbound_file_ids.any?
          files = current_workspace.inbound_files.where(id: inbound_file_ids)
          objective.inbound_files << files
        end

        draft.update!(
          status: "finalized",
          finalized_objective: objective,
          brief_json: normalized_brief,
          suggested_goal: suggested_goal,
          missing_fields: ObjectivePlanningInputBuilder.missing_fields(normalized_brief, draft.template_key),
          ready_to_finalize: true
        )
      end

      ObjectiveKickoff.new.call(objective) if objective.status == "active"

      render json: {
        objective: serialize_objective(objective.reload),
        objective_draft: serialize_objective_draft(draft.reload)
      }, status: :created
    end

    private

    def find_draft!
      prune_stale_drafts!
      current_workspace.objective_drafts.includes(:objective_draft_messages).find(params[:id])
    end

    def apply_composer_turn!(draft)
      turn = ObjectiveComposer.new.call(draft)

      draft.transaction do
        draft.objective_draft_messages.create!(
          role: "assistant",
          content: turn.fetch("assistant_message")
        )
        draft.update!(
          brief_json: turn.fetch("brief_json"),
          suggested_goal: turn.fetch("suggested_goal"),
          assistant_message: turn.fetch("assistant_message"),
          missing_fields: turn.fetch("missing_fields"),
          ready_to_finalize: turn.fetch("ready_to_finalize")
        )
      end
    end

    def resolved_finalize_brief(draft)
      if finalize_params[:brief_json].present?
        ObjectivePlanningInputBuilder.normalize_brief(finalize_params[:brief_json])
      else
        ObjectivePlanningInputBuilder.normalize_brief(draft.brief_json)
      end
    end

    def prune_stale_drafts!
      current_workspace.objective_drafts.stale_unfinalized.find_each(&:destroy)
    end

    def draft_create_params
      params.require(:objective_draft).permit(:template_key, :seed_text, :created_by_profile_id)
    end

    def finalize_params
      params.fetch(:objective_draft, {}).permit(
        :goal,
        :status,
        :priority,
        brief_json: [
          :deliverable,
          { context: [], success_criteria: [], constraints: [], preferences: [], open_questions: [] }
        ]
      )
    end
  end
end
