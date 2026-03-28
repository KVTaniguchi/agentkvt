# frozen_string_literal: true

module V1
  # iOS (or any client) POSTs here after sending a chat message so the Mac agent can
  # poll `V1::Agent::ChatWakesController` off-LAN — no local webhook required.
  class ChatWakesController < V1::BaseController
    def create
      current_workspace.update!(chat_wake_requested_at: Time.current)
      head :accepted
    end
  end
end
