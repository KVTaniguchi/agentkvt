module V1
  module Agent
    class MissionActionItemsController < BaseController
      def index
        mission = current_workspace.missions.find(params[:mission_id])
        action_items = mission.action_items.where(is_handled: false).recent_first.limit(20)
        render json: { action_items: action_items.map { |i| serialize_action_item(i) } }
      end

      def create
        mission = current_workspace.missions.find(params[:mission_id] || params[:id])
        params_data = action_item_params
        content_hash = ActionItem.compute_hash(params_data[:system_intent], params_data[:payload_json])

        # Find an existing unhandled action with identical content, or start a new one.
        # This prevents the same suggestion from being duplicated when a mission re-runs.
        action_item = current_workspace.action_items
          .find_or_initialize_by(content_hash: content_hash, is_handled: false)

        action_item.assign_attributes(params_data.merge(source_mission: mission))
        action_item.timestamp = Time.current
        action_item.save!

        status = action_item.previously_new_record? ? :created : :ok
        render json: { action_item: serialize_action_item(action_item) }, status: status
      end

      private

      def action_item_params
        params.require(:action_item).permit(
          :owner_profile_id,
          :title,
          :system_intent,
          :relevance_score,
          :timestamp,
          :created_by,
          payload_json: {}
        )
      end
    end
  end
end
