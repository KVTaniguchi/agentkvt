module V1
  class ObjectiveFeedbacksController < BaseController
    def update
      feedback = find_feedback
      return if ensure_reviewable!(feedback)

      ObjectiveFeedback.transaction do
        feedback.update!(objective_feedback_params)
        attach_feedback_inbound_files!(feedback)
        feedback.follow_up_tasks.proposed.destroy_all
        ObjectiveFeedbackPlanner.new.call(feedback)
        ObjectiveFeedbackLifecycle.new.refresh!(feedback.reload)
      end

      ObjectiveKickoff.new.call(feedback.objective.reload) if feedback.reload.status == "queued"

      render json: serialize_objective_feedback_mutation(feedback.reload)
    rescue StandardError => error
      feedback.update_column(:status, "failed") if defined?(feedback) && feedback&.persisted?
      raise error
    end

    def approve_plan
      feedback = find_feedback
      proposed_tasks = feedback.follow_up_tasks.proposed

      if proposed_tasks.none?
        return render json: { error: "No follow-up plan is waiting for approval" }, status: :unprocessable_entity
      end

      Task.transaction do
        proposed_tasks.find_each do |task|
          task.update!(status: "pending")
        end
      end

      ObjectiveFeedbackLifecycle.new.refresh!(feedback.reload)
      ObjectiveKickoff.new.call(feedback.objective.reload) if feedback.reload.status == "queued"

      render json: serialize_objective_feedback_mutation(feedback.reload)
    end

    def regenerate_plan
      feedback = find_feedback
      return if ensure_reviewable!(feedback)

      ObjectiveFeedback.transaction do
        feedback.follow_up_tasks.proposed.destroy_all
        ObjectiveFeedbackPlanner.new.call(feedback)
        ObjectiveFeedbackLifecycle.new.refresh!(feedback.reload)
      end

      ObjectiveKickoff.new.call(feedback.objective.reload) if feedback.reload.status == "queued"

      render json: serialize_objective_feedback_mutation(feedback.reload)
    rescue StandardError => error
      feedback.update_column(:status, "failed") if defined?(feedback) && feedback&.persisted?
      raise error
    end

    private

    def find_feedback
      objective = current_workspace.objectives.find(params[:objective_id])
      objective.objective_feedbacks.find(params[:id])
    end

    def ensure_reviewable!(feedback)
      if feedback.follow_up_tasks.empty?
        render json: { error: "This feedback does not have a follow-up plan yet" }, status: :unprocessable_entity
        return true
      end

      if feedback.follow_up_tasks.where.not(status: "proposed").exists?
        render json: { error: "Only follow-up plans that have not started can be edited or regenerated" }, status: :unprocessable_entity
        return true
      end

      false
    end

    def objective_feedback_params
      params.require(:objective_feedback).permit(
        :content,
        :feedback_kind,
        :task_id,
        :research_snapshot_id
      )
    end

    def attach_feedback_inbound_files!(feedback)
      ids = params.dig(:objective_feedback, :inbound_file_ids)
      return if ids.blank?

      files = feedback.objective.workspace.inbound_files.where(id: Array(ids))
      feedback.inbound_files << files.reject { |f| feedback.inbound_file_ids.include?(f.id) }
    end
  end
end
