module V1
  module Agent
    # Called by the Mac agent after running multi_step_search for a task.
    # Upserts a ResearchSnapshot keyed by (objective_id, key) and tracks delta.
    class ResearchSnapshotsController < BaseController
      def create
        objective = current_workspace.objectives.find(params[:objective_id])
        task_id = params[:task_id].presence

        snapshot = objective.research_snapshots.find_or_initialize_by(key: snapshot_params[:key])

        if snapshot.persisted?
          if snapshot.value != snapshot_params[:value]
            snapshot.previous_value = snapshot.value
            snapshot.delta_note = "Changed from #{snapshot.value} to #{snapshot_params[:value]}"
          else
            # Same value: clear any stale delta_note so DeltaMonitorJob doesn't re-alert.
            snapshot.delta_note = nil
          end
        end

        snapshot.assign_attributes(
          value: snapshot_params[:value],
          task_id: task_id,
          checked_at: Time.current
        )
        snapshot.save!

        # Update parent task status if a task_id was supplied
        if task_id
          Task.find_by(id: task_id)&.update!(
            status: "completed",
            result_summary: snapshot_params[:value].truncate(500)
          )
        end

        render json: { research_snapshot: serialize_research_snapshot(snapshot) }, status: :created
      end

      private

      def snapshot_params
        params.require(:research_snapshot).permit(:key, :value)
      end
    end
  end
end
