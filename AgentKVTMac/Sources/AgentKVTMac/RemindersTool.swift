import EventKit
import Foundation

/// Create a tool that writes new reminders to the system Reminders app via EventKit.
public func makeWriteReminderTool() -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "write_reminder",
        name: "write_reminder",
        description: """
            Create a new reminder in the system Reminders app.
            Use this when a mission surfaces a task the user should follow up on manually.
            """,
        parameters: .init(
            type: "object",
            properties: [
                "title": .init(
                    type: "string",
                    description: "The reminder title (required)."
                ),
                "notes": .init(
                    type: "string",
                    description: "Optional notes or context for the reminder."
                ),
                "due_date": .init(
                    type: "string",
                    description: "Optional ISO 8601 due date (e.g. '2025-04-10T09:00:00'). Omit if no specific due time is needed."
                )
            ],
            required: ["title"]
        ),
        handler: { args in
            guard let title = args["title"] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "Error: title is required."
            }
            let notes = args["notes"] as? String
            let dueDateString = args["due_date"] as? String
            return await RemindersToolHandler.createReminder(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes,
                dueDateString: dueDateString
            )
        }
    )
}

enum RemindersToolHandler {
    static func createReminder(title: String, notes: String?, dueDateString: String?) async -> String {
        let store = EKEventStore()

        let granted: Bool
        do {
            granted = try await store.requestFullAccessToReminders()
        } catch {
            return "Error: Reminders access request failed: \(error.localizedDescription)"
        }
        guard granted else {
            return "Error: Reminders access denied. Grant access in System Settings > Privacy & Security > Reminders."
        }

        guard let calendar = store.defaultCalendarForNewReminders() else {
            return "Error: No default Reminders list available."
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar

        if let notes = notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reminder.notes = notes
        }

        if let dueDateString = dueDateString, !dueDateString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
            if let date = iso.date(from: dueDateString) {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: date
                )
            }
        }

        do {
            try store.save(reminder, commit: true)
            return "Reminder created: '\(title)'"
        } catch {
            return "Error saving reminder: \(error.localizedDescription)"
        }
    }
}
