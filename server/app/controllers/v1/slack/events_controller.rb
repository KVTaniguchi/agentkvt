module V1
  module Slack
    class EventsController < ApplicationController
      def create
        signing_secret = ENV["SLACK_SIGNING_SECRET"].to_s
        raw_body = request.body.read.to_s
        request.body.rewind if request.body.respond_to?(:rewind)

        begin
          ::Slack::SignatureVerifier.verify!(
            signing_secret: signing_secret,
            request_body: raw_body,
            timestamp_header: request.headers["X-Slack-Request-Timestamp"].to_s,
            signature_header: request.headers["X-Slack-Signature"].to_s
          )
        rescue ::Slack::SignatureVerifier::MissingSigningSecretError
          return head :internal_server_error
        rescue ::Slack::SignatureVerifier::StaleRequestError, ::Slack::SignatureVerifier::InvalidSignatureError
          return head :unauthorized
        end

        payload = JSON.parse(raw_body)

        if payload["type"] == "url_verification"
          return render json: { challenge: payload["challenge"] }
        end

        if payload["type"] == "event_callback"
          ::Slack::IngestionService.call(payload)
        end

        head :ok
      rescue JSON::ParserError
        head :bad_request
      end
    end
  end
end
