import Foundation

/// Shared checks for objective `write_objective_snapshot` values (Mac + API alignment with Rails).
enum ObjectiveResearchSnapshotPayload {
    /// True when the value is a top-level JSON object or array (including truncated or malformed blobs).
    /// We reject on the opening character alone so that truncated tool-call payloads (which fail
    /// JSON deserialization) are still caught. Valid JSON is never an acceptable plain-language finding.
    static func looksLikeJSONStructure(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    /// Non-nil when the value must not be uploaded (caller should show this to the model).
    static func clientRejectionMessageIfInvalid(_ text: String) -> String? {
        if looksLikeJSONStructure(text) {
            return "Snapshot value must be plain-language prose, not JSON. Summarize findings, then call write_objective_snapshot again."
        }
        return nil
    }
}
