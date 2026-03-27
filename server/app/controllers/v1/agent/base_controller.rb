module V1
  module Agent
    class BaseController < V1::BaseController
      include ActionController::HttpAuthentication::Token::ControllerMethods

      before_action :authenticate_agent!

      private

      def authenticate_agent!
        expected_token = ENV["AGENTKVT_AGENT_TOKEN"].to_s
        return if expected_token.blank?

        authenticate_or_request_with_http_token do |token, _options|
          ActiveSupport::SecurityUtils.secure_compare(token, expected_token)
        end
      end
    end
  end
end
