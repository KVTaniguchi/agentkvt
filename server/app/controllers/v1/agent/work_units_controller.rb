module V1
  module Agent
    class WorkUnitsController < BaseController
      def index
        work_units = current_workspace.work_units
        work_units = work_units.by_state(params[:state]) if params[:state].present?
        work_units = work_units.recent_first
        render json: { work_units: work_units.map { |wu| serialize_work_unit(wu) } }
      end

      def create
        work_unit = current_workspace.work_units.create!(work_unit_params)
        render json: { work_unit: serialize_work_unit(work_unit) }, status: :created
      end

      def update
        work_unit = current_workspace.work_units.find(params[:id])
        work_unit.update!(work_unit_params)
        render json: { work_unit: serialize_work_unit(work_unit) }
      end

      def destroy
        work_unit = current_workspace.work_units.find(params[:id])
        work_unit.destroy!
        head :no_content
      end

      private

      def work_unit_params
        params.require(:work_unit).permit(
          :title,
          :category,
          :objective_id,
          :source_task_id,
          :work_type,
          :state,
          :active_phase_hint,
          :priority,
          :claimed_until,
          :worker_label,
          :last_heartbeat_at,
          :created_by_profile_id,
          mound_payload: {}
        )
      end
    end
  end
end
