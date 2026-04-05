module V1
  class ChatMessagesController < BaseController
    def create
      thread = current_workspace.chat_threads.find(params[:chat_thread_id])
      message = thread.chat_messages.create!(
        chat_message_params.merge(
          role: "user",
          status: "pending"
        )
      )
      current_workspace.request_chat_wake!

      render json: { chat_message: serialize_chat_message(message) }, status: :created
    end

    private

    def chat_message_params
      params.require(:chat_message).permit(:id, :content, :author_profile_id)
    end
  end
end
