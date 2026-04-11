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
    # workspace: optional Workspace; used to look up a stored bot token.
    #            Falls back to SLACK_BOT_TOKEN env var.
    def self.call(channel:, text:, workspace: nil)
      new(channel: channel, text: text, workspace: workspace).call
    end

    def initialize(channel:, text:, workspace: nil)
      @channel   = channel
      @text      = text
      @workspace = workspace
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
      if @workspace
        cred = WorkspaceProviderCredential.find_by(workspace: @workspace, provider: "slack")
        return cred.secret_value if cred&.secret_value.present?
      end

      token = ENV["SLACK_BOT_TOKEN"].presence
      raise TokenMissingError, "No Slack bot token available" unless token

      token
    end
  end
end
