# frozen_string_literal: true

module V1
  # iOS (or any client) POSTs here after sending a chat message so the Mac agent can
  # react via LISTEN (fast path) or poll `V1::Agent::ChatWakesController` off-LAN.
  class ChatWakesController < V1::BaseController
    def create
      current_workspace.update!(chat_wake_requested_at: Time.current)

      # Emit a Postgres NOTIFY so any agent running LISTEN receives it immediately
      # without waiting for its next poll interval.
      ActiveRecord::Base.connection.execute("NOTIFY agentkvt_chat_wake")

      head :accepted
    end
  end
end
