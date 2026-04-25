module V1
  module Agent
    class InboundEmailsController < BaseController
      def create
        email = current_workspace.inbound_emails.find_or_initialize_by(message_id: email_params[:message_id])

        if email.new_record?
          email.assign_attributes(email_params.except(:message_id))
          email.save!
          EmailMessageProcessorJob.perform_later(email.id)
        end

        render json: { inbound_email: serialize_inbound_email(email) }, status: :created
      end

      private

      def email_params
        params.require(:inbound_email).permit(:message_id, :from_address, :subject, :body_text)
      end

      def serialize_inbound_email(email)
        {
          id: email.id,
          message_id: email.message_id,
          from_address: email.from_address,
          subject: email.subject,
          created_at: email.created_at
        }
      end
    end
  end
end
