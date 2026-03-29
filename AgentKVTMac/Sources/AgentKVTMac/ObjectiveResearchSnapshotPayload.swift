import Foundation

/// Shared checks for objective `write_objective_snapshot` values (Mac + API alignment with Rails).
enum ObjectiveResearchSnapshotPayload {
    /// True when the model leaked a JSON tool payload as the snapshot body.
    static func looksLikeRawToolJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["tool_calls"] != nil
        else { return false }
        return true
    }

    /// Non-nil when the value must not be uploaded (caller should show this to the model).
    static func clientRejectionMessageIfInvalid(_ text: String) -> String? {
        if looksLikeRawToolJSON(text) {
            return "Snapshot value looks like raw tool-call JSON. Summarize findings in plain language, then call write_objective_snapshot again."
        }
        return nil
    }
}
