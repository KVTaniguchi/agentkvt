import Foundation

/// Shared checks for objective `write_objective_snapshot` values (Mac + API alignment with Rails).
enum ObjectiveResearchSnapshotPayload {
    /// True when the value is a top-level JSON object or array (including leaked tool-call payloads).
    static func looksLikeJSONStructure(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return false }
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return false }
        return obj is NSDictionary || obj is NSArray
    }

    /// Non-nil when the value must not be uploaded (caller should show this to the model).
    static func clientRejectionMessageIfInvalid(_ text: String) -> String? {
        if looksLikeJSONStructure(text) {
            return "Snapshot value must be plain-language prose, not JSON. Summarize findings, then call write_objective_snapshot again."
        }
        return nil
    }
}
