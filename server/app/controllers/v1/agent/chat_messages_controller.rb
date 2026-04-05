module V1
  module Agent
    class ChatMessagesController < BaseController
      def claim_next
        payload = nil

        ChatMessage.transaction do
          pending = current_workspace.chat_messages
            .joins(:chat_thread)
            .where(role: "user", status: "pending")
            .order(timestamp: :asc, created_at: :asc)
            .lock("FOR UPDATE SKIP LOCKED")
            .first

          if pending
            pending.update!(status: "processing", error_message: nil)
            thread = pending.chat_thread.reload
            messages = thread.chat_messages.chronological.to_a

            payload = {
              pending: true,
              chat_thread: serialize_chat_thread(thread),
              chat_message: serialize_chat_message(pending),
              chat_messages: messages.map { |message| serialize_chat_message(message) }
            }
          end
        end

        render json: payload || { pending: false }
      end

      def complete
        pending = current_workspace.chat_messages.find(params[:id])
        assistant_message = nil

        ChatMessage.transaction do
          pending.update!(status: "completed", error_message: nil)
          assistant_message = pending.chat_thread.chat_messages.create!(
            role: "assistant",
            content: assistant_message_params.fetch("content"),
            status: "completed"
          )
        end

        render json: {
          chat_message: serialize_chat_message(pending.reload),
          assistant_message: serialize_chat_message(assistant_message)
        }
      end

      def fail
        pending = current_workspace.chat_messages.find(params[:id])
        pending.update!(status: "failed", error_message: failure_params.fetch("error_message"))

        render json: { chat_message: serialize_chat_message(pending) }
      end

      private

      def assistant_message_params
        params.require(:assistant_message).permit(:content)
      end

      def failure_params
        params.require(:chat_message).permit(:error_message)
      end
    end
  end
end
