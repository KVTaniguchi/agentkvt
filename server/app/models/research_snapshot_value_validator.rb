# frozen_string_literal: true

# Rejects objective research snapshot values that are JSON blobs (including leaked
# tool-call payloads), which should never be persisted as prose "findings".
module ResearchSnapshotValueValidator
  module_function

  # True when +text+ parses as a top-level JSON object or array (including {"tool_calls": ...}).
  def json_structure_blob?(text)
    stripped = text.to_s.strip
    return false if stripped.blank?
    return false unless stripped.start_with?("{", "[")

    parsed = JSON.parse(stripped)
    parsed.is_a?(Hash) || parsed.is_a?(Array)
  rescue JSON::ParserError
    false
  end
end
