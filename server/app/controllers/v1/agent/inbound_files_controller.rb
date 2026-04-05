module V1
  module Agent
    class InboundFilesController < BaseController
      def index
        files = current_workspace.inbound_files
          .where(is_processed: false)
          .order(timestamp: :asc, created_at: :asc)
          .limit(limit_param)

        render json: { inbound_files: files.map { |inbound_file| serialize_inbound_file(inbound_file, include_data: true) } }
      end

      def mark_processed
        inbound_file = current_workspace.inbound_files.find(params[:id])
        inbound_file.update!(is_processed: true, processed_at: Time.current)

        render json: { inbound_file: serialize_inbound_file(inbound_file) }
      end

      private

      def limit_param
        requested = params.fetch(:limit, 25).to_i
        requested = 25 if requested <= 0
        [requested, 100].min
      end
    end
  end
end
