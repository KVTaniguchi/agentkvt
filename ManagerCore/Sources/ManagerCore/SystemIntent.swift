import Foundation

/// Describes a single field in an ActionItem's payloadJson for a given SystemIntent.
/// This is the canonical schema used by both the LLM tool definition and the iOS intent router.
public struct PayloadField: Sendable {
    public let key: String
    public let valueType: String
    public let description: String
    public let required: Bool

    public init(key: String, valueType: String, description: String, required: Bool) {
        self.key = key
        self.valueType = valueType
        self.description = description
        self.required = required
    }
}

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

    /// Canonical payload schema for this intent. This is the single source of truth for
    /// which keys belong in payloadJson — used by the LLM tool description and the iOS router.
    public var payloadFields: [PayloadField] {
        switch self {
        case .calendarCreate:
            return [
                PayloadField(key: "eventTitle", valueType: "string", description: "Title of the calendar event", required: true),
                PayloadField(key: "startDate", valueType: "ISO-8601 string", description: "Start date and time", required: true),
                PayloadField(key: "durationMinutes", valueType: "integer", description: "Duration in minutes, default 60", required: false),
                PayloadField(key: "notes", valueType: "string", description: "Event notes", required: false)
            ]
        case .mailReply:
            return [
                PayloadField(key: "toAddress", valueType: "string", description: "Recipient email address", required: true),
                PayloadField(key: "subject", valueType: "string", description: "Email subject line", required: true),
                PayloadField(key: "draftBody", valueType: "string", description: "Draft body text", required: true)
            ]
        case .reminderAdd:
            return [
                PayloadField(key: "reminderTitle", valueType: "string", description: "Title of the reminder", required: true),
                PayloadField(key: "dueDate", valueType: "ISO-8601 string", description: "Due date and time", required: false),
                PayloadField(key: "notes", valueType: "string", description: "Reminder notes", required: false)
            ]
        case .urlOpen:
            return [
                PayloadField(key: "url", valueType: "string", description: "Absolute URL to open", required: true),
                PayloadField(key: "label", valueType: "string", description: "Display label for the link", required: false)
            ]
        }
    }
}
