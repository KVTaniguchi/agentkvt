require "base64"

module V1
  class InboundFilesController < BaseController
    MAX_FILE_BYTES = 10.megabytes

    def index
      files = current_workspace.inbound_files.recent_first.limit(limit_param)
      render json: { inbound_files: files.map { |inbound_file| serialize_inbound_file(inbound_file) } }
    end

    def create
      attrs = inbound_file_params.to_h
      file_data = extract_file_data!(attrs)
      inbound_file = current_workspace.inbound_files.create!(
        attrs.merge(
          file_data: file_data,
          byte_size: file_data.bytesize
        )
      )

      render json: { inbound_file: serialize_inbound_file(inbound_file) }, status: :created
    rescue ArgumentError => error
      render json: { error: error.message }, status: :bad_request
    end

    private

    def inbound_file_params
      params.require(:inbound_file).permit(:id, :file_name, :content_type, :uploaded_by_profile_id, :file_base64, :file)
    end

    def extract_file_data!(attrs)
      if (upload = attrs.delete("file"))
        raw = upload.read
        raise ArgumentError, "Inbound file exceeds the 10 MB limit" if raw.bytesize > MAX_FILE_BYTES
        raw
      elsif (file_base64 = attrs.delete("file_base64"))
        decode_base64_file!(file_base64)
      else
        raise ArgumentError, "inbound_file[file] or inbound_file[file_base64] is required"
      end
    end

    def decode_base64_file!(file_base64)
      decoded = Base64.strict_decode64(file_base64)
      raise ArgumentError, "Inbound file exceeds the 10 MB limit" if decoded.bytesize > MAX_FILE_BYTES
      decoded
    rescue ArgumentError => error
      if error.message.include?("strict_decode64")
        raise ArgumentError, "inbound_file[file_base64] must be valid base64"
      end
      raise
    end

    def limit_param
      requested = params.fetch(:limit, 100).to_i
      requested = 100 if requested <= 0
      [requested, 250].min
    end
  end
end
