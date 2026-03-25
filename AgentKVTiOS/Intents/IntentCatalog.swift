import AppIntents
import EventKit
import Foundation

// MARK: - Calendar Event

/// Creates a calendar event from an agent recommendation without leaving the app.
struct CreateCalendarEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Calendar Event"
    static let description = IntentDescription(
        "Schedule a meeting or appointment suggested by the agent.",
        categoryName: "AgentKVT"
    )

    @Parameter(title: "Event Title")
    var eventTitle: String

    @Parameter(title: "Start Date")
    var startDate: Date

    @Parameter(title: "Duration (minutes)", default: 60)
    var durationMinutes: Int

    @Parameter(title: "Notes")
    var notes: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Schedule \(\.$eventTitle) on \(\.$startDate)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else {
            throw AgentIntentError.permissionDenied("Calendar")
        }
        let event = EKEvent(eventStore: store)
        event.title = eventTitle
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(Double(durationMinutes) * 60)
        event.notes = notes
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
        let formatted = startDate.formatted(date: .abbreviated, time: .shortened)
        return .result(dialog: "Scheduled '\(eventTitle)' for \(formatted).")
    }
}

// MARK: - Mail Reply

/// Opens Mail.app with a pre-drafted reply body so the user can review before sending.
struct DraftMailReplyIntent: AppIntent {
    static let title: LocalizedStringResource = "Draft Mail Reply"
    static let description = IntentDescription(
        "Open Mail with an agent-drafted reply ready to edit and send.",
        categoryName: "AgentKVT"
    )

    @Parameter(title: "To Address")
    var toAddress: String

    @Parameter(title: "Subject")
    var subject: String

    @Parameter(title: "Draft Body")
    var draftBody: String

    static var parameterSummary: some ParameterSummary {
        Summary("Draft reply to \(\.$toAddress) re: \(\.$subject)")
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        let encodedTo = toAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedSub = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = draftBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "mailto:\(encodedTo)?subject=\(encodedSub)&body=\(encodedBody)") else {
            throw AgentIntentError.invalidPayload("Could not construct mailto URL.")
        }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

// MARK: - Reminder

/// Adds a reminder to the system Reminders app, optionally with a due date and alert.
struct AddReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Reminder"
    static let description = IntentDescription(
        "Save an agent-generated reminder to Apple Reminders.",
        categoryName: "AgentKVT"
    )

    @Parameter(title: "Reminder Title")
    var reminderTitle: String

    @Parameter(title: "Due Date")
    var dueDate: Date?

    @Parameter(title: "Notes")
    var notes: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Remind me: \(\.$reminderTitle)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = EKEventStore()
        guard try await store.requestFullAccessToReminders() else {
            throw AgentIntentError.permissionDenied("Reminders")
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = reminderTitle
        reminder.notes = notes
        reminder.calendar = store.defaultCalendarForNewReminders()
        if let due = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due
            )
            reminder.addAlarm(EKAlarm(absoluteDate: due.addingTimeInterval(-900))) // 15 min alert
        }
        try store.save(reminder, commit: true)
        return .result(dialog: "Reminder added: \(reminderTitle)")
    }
}

// MARK: - Open URL

/// Opens any URL — covers deep links, document URLs, and web results.
struct OpenAgentURLIntent: AppIntent {
    static let title: LocalizedStringResource = "Open URL"
    static let description = IntentDescription(
        "Open a URL recommended by the agent — deep link, document, or web page.",
        categoryName: "AgentKVT"
    )

    @Parameter(title: "URL")
    var targetURL: URL

    @Parameter(title: "Label")
    var label: String?

    func perform() async throws -> some IntentResult & OpensIntent {
        return .result(opensIntent: OpenURLIntent(targetURL))
    }
}

// MARK: - Error Types

enum AgentIntentError: Error, CustomLocalizedStringResourceConvertible {
    case permissionDenied(String)
    case invalidPayload(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .permissionDenied(let app):
            return "Permission denied for \(app). Update Settings to allow access."
        case .invalidPayload(let detail):
            return "Invalid action payload: \(detail)"
        }
    }
}
