module V1
  class MissionsController < BaseController
    def index
      missions = current_workspace.missions.recent_first
      render json: { missions: missions.map { |mission| serialize_mission(mission) } }
    end

    def create
      mission = current_workspace.missions.new
      attributes = mission_params.to_h
      mission.id = attributes.delete("id") if attributes["id"].present?
      mission.assign_attributes(attributes)
      mission.save!

      render json: { mission: serialize_mission(mission) }, status: :created
    end

    def update
      mission = current_workspace.missions.find(params[:id])
      mission.update!(mission_params)

      render json: { mission: serialize_mission(mission) }
    end

    private

    def mission_params
      params.require(:mission).permit(
        :id,
        :owner_profile_id,
        :source_device_id,
        :mission_name,
        :system_prompt,
        :trigger_schedule,
        :is_enabled,
        :last_run_at,
        :source_updated_at,
        allowed_mcp_tools: []
      )
    end
  end
end
