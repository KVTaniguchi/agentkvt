module V1
  class LifeContextEntriesController < BaseController
    def index
      entries = current_workspace.life_context_entries.order(:key)
      render json: { life_context_entries: entries.map { |entry| serialize_life_context_entry(entry) } }
    end

    def update
      path_key = normalized_key(params[:key])
      payload_key = normalized_key(params.dig(:life_context_entry, :key))
      value = params.dig(:life_context_entry, :value).to_s

      entry = current_workspace.life_context_entries.find_or_initialize_by(key: path_key)
      entry.id ||= parsed_uuid(params.dig(:life_context_entry, :id)) || entry.id
      entry.key = payload_key.presence || path_key
      entry.value = value

      status = entry.new_record? ? :created : :ok
      entry.save!

      render json: { life_context_entry: serialize_life_context_entry(entry) }, status: status
    end

    private

    def normalized_key(raw)
      raw.to_s.strip
    end

    def parsed_uuid(raw)
      value = raw.to_s.strip
      return if value.blank?
      return value if value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i)

      nil
    end
  end
end
