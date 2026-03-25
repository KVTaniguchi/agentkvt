import Foundation

/// Canonical system intents supported by the iOS router.
///
/// Raw values are the persisted string contract used in `ActionItem.systemIntent`.
public enum SystemIntent: String, CaseIterable, Sendable {
    case calendarCreate = "calendar.create"
    case mailReply = "mail.reply"
    case reminderAdd = "reminder.add"
    case urlOpen = "url.open"

    /// Backward-compatible aliases that may still be produced by older prompts/tests.
    /// These should be normalized by producers before persistence.
    public static let legacyAliases: [String: SystemIntent] = [
        "open_url": .urlOpen
    ]

    public static func normalizedRawValue(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let canonical = legacyAliases[trimmed] {
            return canonical.rawValue
        }
        return trimmed
    }
}
