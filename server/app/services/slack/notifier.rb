module Slack
  class Notifier
    SLACK_API_POST = "https://slack.com/api/chat.postMessage"

    class Error < StandardError; end
    class TokenMissingError < Error; end
    class ApiError < Error; end

    # Send a plain-text or markdown message to a Slack channel or DM.
    #
    # channel: Slack channel ID ("C0ASF73V75F"), user ID for DMs ("U0ASWJ44S2C"),
    #          or channel name ("#general").
    # text:    The message body (plain text or Slack mrkdwn).
    # workspace: accepted for API compatibility but unused; token comes from SLACK_BOT_TOKEN.
    def self.call(channel:, text:, workspace: nil)
      new(channel: channel, text: text).call
    end

    def initialize(channel:, text:)
      @channel = channel
      @text    = text
    end

    def call
      token = resolve_token!

      uri  = URI(SLACK_API_POST)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      req = Net::HTTP::Post.new(uri.path)
      req["Authorization"] = "Bearer #{token}"
      req["Content-Type"]  = "application/json; charset=utf-8"
      req.body = { channel: @channel, text: @text }.to_json

      resp = http.request(req)
      body = JSON.parse(resp.body)

      unless body["ok"]
        raise ApiError, "Slack API error: #{body['error']} (channel=#{@channel})"
      end

      body
    end

    private

    def resolve_token!
      token = ENV["SLACK_BOT_TOKEN"].presence
      raise TokenMissingError, "No Slack bot token available" unless token

      token
    end
  end
end
