# frozen_string_literal: true

module V1
  module Agent
    # Agents POST here on startup and every ~15s to register their capabilities
    # and signal that they are online. TaskExecutorJob uses this table to route
    # tasks to capable agents instead of the hardcoded webhook URL.
    class RegistrationsController < BaseController
      def upsert
        reg = current_workspace.agent_registrations.find_or_initialize_by(
          agent_id: registration_params[:agent_id]
        )
        reg.assign_attributes(
          capabilities: registration_params[:capabilities] || [],
          webhook_url: registration_params[:webhook_url],
          status: "online",
          last_seen_at: Time.current
        )
        reg.save!

        if registration_params[:email_address].present?
          identity = current_workspace.agent_identity || current_workspace.create_agent_identity!(display_name: "AgentKVT")
          identity.update!(from_email: registration_params[:email_address])
        end

        render json: { agent_registration: serialize_registration(reg) }, status: reg.previously_new_record? ? :created : :ok
      end

      private

      def registration_params
        params.require(:agent_registration).permit(:agent_id, :webhook_url, :email_address, capabilities: [])
      end

      end
    end
  end
end
