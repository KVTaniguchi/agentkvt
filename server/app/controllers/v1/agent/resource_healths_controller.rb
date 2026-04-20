module V1
  module Agent
    class ResourceHealthsController < BaseController
      def index
        resource_healths = current_workspace.resource_healths.recent_first
        render json: { resource_healths: resource_healths.map { |rh| serialize_resource_health(rh) } }
      end

      def upsert
        record = ResourceHealth.upsert_failure!(
          workspace: current_workspace,
          resource_key: params.require(:resource_key),
          error_message: params[:error_message]
        )
        render json: { resource_health: serialize_resource_health(record) }, status: :ok
      end

      def destroy
        record = current_workspace.resource_healths.find_by!(resource_key: params[:id])
        record.destroy!
        head :no_content
      end
    end
  end
end
