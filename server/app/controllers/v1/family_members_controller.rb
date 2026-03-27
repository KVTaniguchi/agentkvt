module V1
  class FamilyMembersController < BaseController
    def index
      family_members = current_workspace.family_members.order(:display_name)
      render json: { family_members: family_members.map { |member| serialize_family_member(member) } }
    end

    def create
      family_member = current_workspace.family_members.new
      attributes = family_member_params.to_h
      family_member.id = attributes.delete("id") if attributes["id"].present?
      family_member.assign_attributes(attributes)
      family_member.save!

      render json: { family_member: serialize_family_member(family_member) }, status: :created
    end

    private

    def family_member_params
      params.require(:family_member).permit(
        :id,
        :display_name,
        :symbol
      )
    end
  end
end
