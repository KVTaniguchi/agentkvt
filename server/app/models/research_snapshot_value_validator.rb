# frozen_string_literal: true

# Rejects objective research snapshot values that are JSON blobs (including leaked
# tool-call payloads), which should never be persisted as prose "findings".
module ResearchSnapshotValueValidator
  module_function

  # True when +text+ looks like a JSON object or array — including truncated or malformed blobs.
  # We reject on the opening character alone so that truncated tool-call payloads (which fail
  # JSON.parse) are still caught. Valid JSON is never an acceptable "plain-language finding".
  def json_structure_blob?(text)
    stripped = text.to_s.strip
    return false if stripped.blank?

    stripped.start_with?("{", "[")
  end
end
