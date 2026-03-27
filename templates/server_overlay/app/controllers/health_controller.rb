class HealthController < ActionController::API
  def show
    render json: {
      ok: true,
      service: "agentkvt-server",
      time: Time.current.utc.iso8601
    }
  end
end
