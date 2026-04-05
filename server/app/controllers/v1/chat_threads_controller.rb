module V1
  class ChatThreadsController < BaseController
    def index
      threads = current_workspace.chat_threads.includes(:chat_messages).recent_first
      render json: { chat_threads: threads.map { |thread| serialize_chat_thread(thread) } }
    end

    def create
      thread = current_workspace.chat_threads.create!(chat_thread_params)
      render json: { chat_thread: serialize_chat_thread(thread) }, status: :created
    end

    def show
      thread = current_workspace.chat_threads.includes(:chat_messages).find(params[:id])
      render json: {
        chat_thread: serialize_chat_thread(thread),
        chat_messages: thread.chat_messages.chronological.map { |message| serialize_chat_message(message) }
      }
    end

    private

    def chat_thread_params
      attrs = params.fetch(:chat_thread, {}).permit(:id, :title, :system_prompt, :created_by_profile_id, allowed_tool_ids: [])
      if attrs.key?(:allowed_tool_ids)
        attrs[:allowed_tool_ids] = Array(attrs[:allowed_tool_ids]).map(&:to_s).map(&:strip).reject(&:blank?)
      end
      attrs
    end
  end
end
