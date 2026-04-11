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

    # Channel IDs where bot/feed messages are allowed through (e.g. RSS feed channels).
    # Set SLACK_FEED_CHANNEL_IDS as a comma-separated list of channel IDs.
    def feed_channel_ids
      @feed_channel_ids ||= ENV.fetch("SLACK_FEED_CHANNEL_IDS", "").split(",").map(&:strip).reject(&:empty?).to_set
    end

    def feed_channel?(channel_id)
      channel_id.present? && feed_channel_ids.include?(channel_id)
    end

    def skip_event?(event)
      return true unless event.is_a?(Hash)
      return true unless event["type"] == "message"

      channel_id = event["channel"].presence

      # Ephemeral / system noise — always skip
      return true if event["subtype"].present? && %w[channel_join channel_leave group_join].include?(event["subtype"])
      return true if event["text"].blank?

      # Bot/feed messages: allow through only from designated feed channels
      is_bot = event["bot_id"].present? || event["subtype"] == "bot_message"
      if is_bot
        return true unless feed_channel?(channel_id)
        # Feed channel bot message — allow, but require text
        return false
      end

      # Human messages: require a user
      return true if event["user"].blank?

      false
    end

    def persist_message!(workspace:, team_id:, event:)
      channel_id = event["channel"].presence
      message_ts = event["ts"].presence
      return :ignored if channel_id.blank? || message_ts.blank?

      is_feed = feed_channel?(channel_id)
      intake_kind = is_feed ? "feed_bot" : "user_typed"

      sanitized_event = PayloadSanitizer.sanitize(event)
      envelope = {
        "event_id"   => @payload["event_id"],
        "event_time" => @payload["event_time"],
        "team_id"    => team_id,
        "event"      => sanitized_event
      }

      record = SlackMessage.find_or_initialize_by(
        workspace_id:  workspace.id,
        slack_team_id: team_id,
        channel_id:    channel_id,
        message_ts:    message_ts
      )

      record.assign_attributes(
        slack_user_id:    event["user"].presence || event["bot_id"].presence,
        text:             event["text"],
        raw_payload_json: envelope,
        intake_kind:      intake_kind,
        trust_tier:       is_feed ? "medium" : "low",
        provenance_json:  {
          "slack_event_id" => @payload["event_id"],
          "api_app_id"     => @payload["api_app_id"]
        }.compact
      )

      record.save!
      SlackMessageProcessorJob.perform_later(record.id)
      :persisted
    end
  end
end
