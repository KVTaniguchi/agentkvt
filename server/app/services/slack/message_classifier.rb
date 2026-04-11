module Slack
  # Classifies an inbound SlackMessage using the local LLM and returns a
  # structured action descriptor.
  #
  # Return shape:
  #   {
  #     "action"    => "notify_user" | "append_research" | "create_objective" | "ignore",
  #     "summary"   => "one-sentence description of the signal",
  #     "urgency"   => "low" | "medium" | "high",
  #     "objective_id" => "<uuid>" | nil   # set when action == "append_research"
  #   }
  class MessageClassifier
    ACTIONS = %w[notify_user append_research create_objective ignore].freeze

    def self.call(slack_message, objectives: [])
      new(slack_message, objectives: objectives).call
    end

    def initialize(slack_message, objectives: [])
      @message    = slack_message
      @objectives = objectives
    end

    def call
      raw = OllamaClient.new.chat(
        messages: build_messages,
        format: "json",
        task: "slack_message_classify",
        options: { num_ctx: 4096, think: false }
      )
      parse(raw)
    rescue => e
      Rails.logger.warn("[Slack::MessageClassifier] LLM error: #{e.message}")
      { "action" => "ignore", "summary" => "", "urgency" => "low", "objective_id" => nil }
    end

    private

    def build_messages
      objectives_block =
        if @objectives.any?
          list = @objectives.map { |o| "- [#{o.id}] #{o.goal}" }.join("\n")
          "Active objectives:\n#{list}"
        else
          "No active objectives."
        end

      system_prompt = <<~PROMPT
        You are a signal-routing agent. Given a Slack message, decide what action to take.

        Possible actions:
        - notify_user: the message contains a significant event worth surfacing immediately (e.g. large market move, breaking news, urgent alert)
        - append_research: the message is relevant context for one of the active objectives listed below
        - create_objective: the message suggests a new research or action goal that does not match any existing objective
        - ignore: the message is noise, casual conversation, or not actionable

        #{objectives_block}

        Rules:
        - Prefer "ignore" over "notify_user" for routine or low-signal messages.
        - Only choose "append_research" if the message clearly relates to one of the listed objectives.
        - Set urgency to "high" only for time-sensitive events (market drops >2%, breaking news, alerts).
        - Return valid JSON only, matching this schema exactly:
          {"action": string, "summary": string, "urgency": string, "objective_id": string|null}
      PROMPT

      [
        { role: "system", content: system_prompt },
        { role: "user",   content: "/no_think\n\nClassify this Slack message:\n\n#{@message.text}" }
      ]
    end

    def parse(raw)
      result = JSON.parse(raw.to_s.strip)
      result["action"]       = "ignore" unless ACTIONS.include?(result["action"])
      result["urgency"]      = "low"    unless %w[low medium high].include?(result["urgency"])
      result["summary"]    ||= ""
      result["objective_id"] = nil unless result["objective_id"].is_a?(String) && result["objective_id"].match?(/\A[0-9a-f-]{36}\z/)
      result
    rescue JSON::ParseError
      Rails.logger.warn("[Slack::MessageClassifier] Could not parse LLM output: #{raw.inspect}")
      { "action" => "ignore", "summary" => "", "urgency" => "low", "objective_id" => nil }
    end
  end
end
