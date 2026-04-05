# frozen_string_literal: true

module V1
  module Agent
    class ChatWakesController < BaseController
      LISTEN_TIMEOUT_SECONDS = 30

      # GET — atomically consumes a pending chat-wake flag set by POST /v1/chat_wake.
      # Used by the Mac agent as a fast-path long-poll: it blocks up to 30s waiting for
      # a Postgres NOTIFY on `agentkvt_chat_wake`, then atomically reads and clears the flag.
      # Returns quickly (sub-100ms) when iOS fires POST /v1/chat_wake.
      def show
        # Open a dedicated raw PG connection so we don't hold a connection-pool slot
        # open for up to LISTEN_TIMEOUT_SECONDS.
        raw_conn = PG.connect(raw_pg_config)
        notified = false

        begin
          raw_conn.exec("LISTEN agentkvt_chat_wake")
          raw_conn.wait_for_notify(LISTEN_TIMEOUT_SECONDS) { notified = true }
        ensure
          raw_conn.exec("UNLISTEN agentkvt_chat_wake") rescue nil
          raw_conn.close rescue nil
        end

        # Whether we were notified or timed out, do the atomic read-and-clear.
        pending = false
        requested_at = nil
        current_workspace.with_lock do
          w = current_workspace.reload
          if w.chat_wake_requested_at.present?
            pending = true
            requested_at = w.chat_wake_requested_at.iso8601
            w.update!(chat_wake_requested_at: nil)
          end
        end

        render json: { pending: pending, requested_at: requested_at, notified: notified }
      end

      private

      def raw_pg_config
        db = ActiveRecord::Base.connection_db_config.configuration_hash
        config = { host: db[:host] || "127.0.0.1", port: db[:port] || 5432 }
        config[:dbname]   = db[:database] if db[:database]
        config[:user]     = db[:username] if db[:username]
        config[:password] = db[:password] if db[:password]
        config
      end
    end
  end
end
