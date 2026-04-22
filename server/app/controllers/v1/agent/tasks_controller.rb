module V1
  module Agent
    class TasksController < BaseController
      def fail
        objective = current_workspace.objectives.find(params[:objective_id])
        task = objective.tasks.find(params[:id])
        error_message = failure_params.fetch("error_message")

        unless task.status == "completed"
          task.update!(
            status: "failed",
            result_summary: error_message.truncate(500),
            claimed_at: nil,
            claimed_by_agent_id: nil
          )
          ObjectiveFeedbackLifecycle.new.refresh!(task.source_feedback.reload) if task.source_feedback.present?
        end

        render json: { task: serialize_task(task.reload) }
      end

      # Releases a stuck claim back to pending so the task can be re-queued.
      # Called by the runner when a supervisor fails due to infrastructure errors
      # (Ollama timeout, backend connectivity) rather than a true task failure.
      def release
        objective = current_workspace.objectives.find(params[:objective_id])
        task = objective.tasks.find(params[:id])

        unless task.status == "completed"
          task.update!(
            status: "pending",
            claimed_at: nil,
            claimed_by_agent_id: nil
          )
          ObjectiveFeedbackLifecycle.new.refresh!(task.source_feedback.reload) if task.source_feedback.present?
        end

        render json: { task: serialize_task(task.reload) }
      end

      private

      def failure_params
        params.require(:task).permit(:error_message)
      end
    end
  end
end
