# frozen_string_literal: true

# Rejects objective research snapshot values that are clearly raw LLM tool-call JSON,
# which should never be persisted as "findings" for humans or downstream stigmergy.
module ResearchSnapshotValueValidator
  module_function

  # True when +text+ parses as a JSON object whose top-level key set includes "tool_calls"
  # (Ollama / OpenAI-style manual tool payloads leaked as assistant text).
  def tool_like_json?(text)
    stripped = text.to_s.strip
    return false if stripped.blank?
    return false unless stripped.start_with?("{")

    parsed = JSON.parse(stripped)
    parsed.is_a?(Hash) && parsed.key?("tool_calls")
  rescue JSON::ParserError
    false
  end
end
