module V1
  class ClientTelemetrySnapshotsController < BaseController
    def create
      snapshot = current_workspace.client_context_snapshots.create!(
        location_snapshot: snapshot_params[:location] || {},
        weather_snapshot: snapshot_params[:weather] || {},
        scheduled_events: snapshot_params[:events_48h] || [],
        raw_payload: params.to_unsafe_h.except(:controller, :action, :workspace_slug)
      )

      render json: { success: true, id: snapshot.id }
    end

    private

    def snapshot_params
      params.permit(
        :timestamp,
        location: {},
        weather: {},
        events_48h: [:id, :title, :start_at, :end_at, :location]
      )
    end
  end
end
