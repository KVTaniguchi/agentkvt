module V1
  module Agent
    # Called by the Mac agent after running multi_step_search for a task.
    # Upserts a ResearchSnapshot keyed by (objective_id, key) and tracks delta.
    class ResearchSnapshotsController < BaseController
      # GET — list snapshots for stigmergic read-before-write (optional task_id narrows to
      # objective-wide + that task's rows).
      def index
        objective = current_workspace.objectives.find(params[:objective_id])
        scope = objective.research_snapshots
        if (tid = params[:task_id].presence) && objective.tasks.exists?(id: tid)
          scope = scope.where("task_id IS NULL OR task_id = ?", tid)
        end

        snapshots = scope.recent_first.limit(200)
        render json: { research_snapshots: snapshots.map { |s| serialize_research_snapshot(s) } }
      end

      def create
        objective = current_workspace.objectives.find(params[:objective_id])
        task_id = params[:task_id].presence
        mark_task_completed = if params.key?(:mark_task_completed)
          ActiveModel::Type::Boolean.new.cast(params[:mark_task_completed])
        else
          task_id.present?
        end

        snapshot = ResearchSnapshot.upsert_for_objective!(
          objective: objective,
          key: snapshot_params[:key],
          value: snapshot_params[:value],
          is_repellent: snapshot_params[:is_repellent],
          repellent_reason: snapshot_params[:repellent_reason],
          repellent_scope: snapshot_params[:repellent_scope],
          snapshot_kind: snapshot_params[:snapshot_kind] || "result",
          task_id: task_id,
          checked_at: Time.current
        )

        if snapshot.has_attribute?("is_repellent") && snapshot[:is_repellent]
          objective.decrement!(:nutrient_density)
        end

        # Update parent task status if a task_id was supplied
        if task_id && mark_task_completed
          task = Task.find_by(id: task_id)
          task&.update!(
            status: "completed",
            result_summary: snapshot_params[:value].truncate(500)
          )
          ObjectiveFeedbackLifecycle.new.refresh!(task.source_feedback.reload) if task&.source_feedback.present?
        end

        render json: { research_snapshot: serialize_research_snapshot(snapshot) }, status: :created
      end

      private

      def snapshot_params
        params.require(:research_snapshot).permit(
          :key, :value, :is_repellent, :repellent_reason, :repellent_scope, :snapshot_kind
        )
      end
    end
  end
end
