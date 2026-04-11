module Slack
  class IngestionService
    def self.call(payload_hash)
      new(payload_hash).call
    end

    def initialize(payload_hash)
      @payload = payload_hash
    end

    def call
      return :ignored unless @payload.is_a?(Hash)
      return :ignored unless @payload["type"] == "event_callback"

      team_id = @payload["team_id"].presence
      workspace = WorkspaceResolver.call(team_id: team_id)
      unless workspace
        Rails.logger.warn("[Slack::IngestionService] Unknown Slack team_id=#{team_id.inspect} — skipping")
        return :unknown_team
      end

      event = @payload["event"]
      return :ignored if skip_event?(event)

      persist_message!(workspace: workspace, team_id: team_id, event: event)
    end

    private

    def skip_event?(event)
      return true unless event.is_a?(Hash)
      return true unless event["type"] == "message"

      # Bot / automation — do not treat as user intake for v1
      return true if event["bot_id"].present?
      return true if event["subtype"] == "bot_message"

      # Ephemeral / system noise (expand later)
      return true if event["subtype"].present? && %w[channel_join channel_leave group_join].include?(event["subtype"])

      return true if event["user"].blank?
      return true if event["text"].blank?

      false
    end

    def persist_message!(workspace:, team_id:, event:)
      channel_id = event["channel"].presence
      message_ts = event["ts"].presence
      return :ignored if channel_id.blank? || message_ts.blank?

      sanitized_event = PayloadSanitizer.sanitize(event)
      envelope = {
        "event_id" => @payload["event_id"],
        "event_time" => @payload["event_time"],
        "team_id" => team_id,
        "event" => sanitized_event
      }

      record = SlackMessage.find_or_initialize_by(
        workspace_id: workspace.id,
        slack_team_id: team_id,
        channel_id: channel_id,
        message_ts: message_ts
      )

      record.assign_attributes(
        slack_user_id: event["user"].presence,
        text: event["text"],
        raw_payload_json: envelope,
        intake_kind: "user_typed",
        trust_tier: "low",
        provenance_json: {
          "slack_event_id" => @payload["event_id"],
          "api_app_id" => @payload["api_app_id"]
        }.compact
      )

      record.save!
      Slack::MessageProcessorJob.perform_later(record.id)
      :persisted
    end
  end
end
