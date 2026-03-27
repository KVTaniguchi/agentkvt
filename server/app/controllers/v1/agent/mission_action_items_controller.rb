module V1
  module Agent
    class MissionActionItemsController < BaseController
      def create
        mission = current_workspace.missions.find(params[:mission_id] || params[:id])
        action_item = current_workspace.action_items.create!(action_item_params.merge(source_mission: mission))

        render json: { action_item: serialize_action_item(action_item) }, status: :created
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
