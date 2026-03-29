class HealthController < ActionController::API
  # Lightweight probe for load balancers; extends with DB + migration signals so you can
  # tell "API up but objectives not migrated" from a generic 404 on POST /v1/objectives.
  def show
    time = Time.current.utc.iso8601
    payload = {
      ok: true,
      service: "agentkvt-server",
      time: time
    }

    begin
      ActiveRecord::Base.connection.execute("SELECT 1")
      objectives = ActiveRecord::Base.connection.data_source_exists?(:objectives)
      payload[:database] = { connected: true, objectives_table: objectives }
      payload[:ready] = objectives
    rescue StandardError => e
      payload[:ok] = false
      payload[:database] = { connected: false, error: e.message }
      payload[:ready] = false
      return render json: payload, status: :service_unavailable
    end

    render json: payload
  end
end
