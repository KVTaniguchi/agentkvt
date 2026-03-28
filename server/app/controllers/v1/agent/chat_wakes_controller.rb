# frozen_string_literal: true

module V1
  module Agent
    class ChatWakesController < BaseController
      # GET — atomically consumes a pending chat-wake flag set by POST /v1/chat_wake.
      def show
        pending = false
        requested_at = nil
        current_workspace.with_lock do
          w = current_workspace
          if w.chat_wake_requested_at.present?
            pending = true
            requested_at = w.chat_wake_requested_at.iso8601
            w.update!(chat_wake_requested_at: nil)
          end
        end

        render json: { pending: pending, requested_at: requested_at }
      end
    end
  end
end
