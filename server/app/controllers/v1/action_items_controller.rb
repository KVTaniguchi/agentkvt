module V1
  class ActionItemsController < BaseController
    def index
      action_items = current_workspace.action_items.recent_first
      action_items = action_items.where(is_handled: ActiveModel::Type::Boolean.new.cast(params[:is_handled])) if params.key?(:is_handled)
      action_items = action_items.limit(limit_param)

      render json: { action_items: action_items.map { |item| serialize_action_item(item) } }
    end

    def handle
      action_item = current_workspace.action_items.find(params[:id])
      action_item.update!(
        is_handled: true,
        handled_at: parsed_time(params[:handled_at]) || Time.current
      )

      render json: { action_item: serialize_action_item(action_item) }
    end

    private

    def limit_param
      requested = params[:limit].to_i
      return 50 if requested <= 0

      [requested, 200].min
    end

    def parsed_time(raw)
      return if raw.blank?

      Time.zone.parse(raw)
    rescue ArgumentError
      nil
    end
  end
end
