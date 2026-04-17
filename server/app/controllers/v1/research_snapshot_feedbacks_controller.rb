module V1
  class ResearchSnapshotFeedbacksController < BaseController
    def create
      objective, snapshot = load_objective_and_snapshot
      feedback = upsert_feedback(objective: objective, snapshot: snapshot)
      invalidate_presentation!(objective)

      render json: { research_snapshot_feedback: serialize_research_snapshot_feedback(feedback) }, status: :created
    end

    def update
      objective, snapshot = load_objective_and_snapshot
      feedback = snapshot.feedback_entries.find(params[:id])
      feedback.update!(feedback_params)
      invalidate_presentation!(objective)

      render json: { research_snapshot_feedback: serialize_research_snapshot_feedback(feedback) }
    end

    private

    def load_objective_and_snapshot
      objective = current_workspace.objectives.find(params[:objective_id])
      snapshot = objective.research_snapshots.find(params[:research_snapshot_id])
      [objective, snapshot]
    end

    def upsert_feedback(objective:, snapshot:)
      attrs = feedback_params.to_h
      attrs["workspace_id"] = current_workspace.id
      attrs["objective_id"] = objective.id
      attrs["research_snapshot_id"] = snapshot.id
      attrs["role"] ||= "user"

      lookup = {
        research_snapshot_id: snapshot.id,
        created_by_profile_id: attrs["created_by_profile_id"],
        role: attrs["role"]
      }

      feedback = current_workspace.research_snapshot_feedbacks.find_or_initialize_by(lookup)
      feedback.assign_attributes(attrs)
      feedback.save!
      feedback
    end

    def feedback_params
      params.require(:research_snapshot_feedback).permit(:created_by_profile_id, :role, :rating, :reason)
    end

    def invalidate_presentation!(objective)
      objective.update_columns(
        presentation_generated_at: nil,
        presentation_enqueued_at: nil
      )
    end
  end
end
