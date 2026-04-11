module Slack
  # Classifies an inbound SlackMessage using the local LLM and returns a
  # structured action descriptor.
  #
  # Return shape:
  #   {
  #     "action"       => "append_research" | "ignore",
  #     "summary"      => "one-sentence description of the signal",
  #     "objective_id" => "<uuid>" | nil   # set when action == "append_research"
  #   }
  class MessageClassifier
    ACTIONS = %w[append_research ignore].freeze

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
        You are a research signal router. Given a Slack message and a list of active objectives, decide whether the message contains new factual information that should be appended as a research finding to one of those objectives.

        #{objectives_block}

        Rules:
        - Choose "append_research" ONLY if the message contains concrete factual information (a price move, a news event, a data point) that directly relates to the goal of one of the listed objectives. Set objective_id to the matching objective's UUID.
        - Choose "ignore" for everything else: casual conversation, questions, vague statements, or messages that don't clearly map to an objective.
        - Do NOT invent objectives or suggest creating new ones.
        - Return valid JSON only, matching this schema exactly:
          {"action": string, "summary": string, "objective_id": string|null}
      PROMPT

      [
        { role: "system", content: system_prompt },
        { role: "user",   content: "/no_think\n\nClassify this Slack message:\n\n#{@message.text}" }
      ]
    end

    def parse(raw)
      result = JSON.parse(raw.to_s.strip)
      result["action"]       = "ignore" unless ACTIONS.include?(result["action"])
      result["summary"]    ||= ""
      result["objective_id"] = nil unless result["objective_id"].is_a?(String) && result["objective_id"].match?(/\A[0-9a-f-]{36}\z/)
      result
    rescue JSON::ParseError
      Rails.logger.warn("[Slack::MessageClassifier] Could not parse LLM output: #{raw.inspect}")
      { "action" => "ignore", "summary" => "", "urgency" => "low", "objective_id" => nil }
    end
  end
end
