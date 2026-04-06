import EventKit
import Foundation

/// Create a tool that reads upcoming events from the system Calendar via EventKit.
public func makeReadCalendarTool() -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "read_calendar",
        name: "read_calendar",
        description: """
            Read upcoming calendar events from the system Calendar app.
            Use this to check the user's schedule before planning time-sensitive tasks or missions.
            """,
        parameters: .init(
            type: "object",
            properties: [
                "days_ahead": .init(
                    type: "string",
                    description: "Optional. Number of days ahead to look (default 7, max 30). Pass as string e.g. '7'."
                ),
                "calendar_name": .init(
                    type: "string",
                    description: "Optional. Filter events to a specific calendar by name. Omit to include all calendars."
                )
            ],
            required: []
        ),
        handler: { args in
            let daysAhead = (args["days_ahead"] as? String).flatMap(Int.init).map { min(max($0, 1), 30) } ?? 7
            let calendarName = args["calendar_name"] as? String
            return await CalendarToolHandler.fetchEvents(daysAhead: daysAhead, calendarName: calendarName)
        }
    )
}

enum CalendarToolHandler {
    static func fetchEvents(daysAhead: Int, calendarName: String?) async -> String {
        let store = EKEventStore()

        let granted: Bool
        do {
            granted = try await store.requestFullAccessToEvents()
        } catch {
            return "Error: Calendar access request failed: \(error.localizedDescription)"
        }
        guard granted else {
            return "Error: Calendar access denied. Grant access in System Settings > Privacy & Security > Calendars."
        }

        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) else {
            return "Error: Could not calculate end date."
        }

        var filteredCalendars: [EKCalendar]? = nil
        if let name = calendarName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let matched = store.calendars(for: .event).filter {
                $0.title.localizedCaseInsensitiveContains(name)
            }
            if matched.isEmpty {
                let available = store.calendars(for: .event).map { $0.title }.joined(separator: ", ")
                return "No calendar matching '\(name)'. Available: \(available.isEmpty ? "(none)" : available)"
            }
            filteredCalendars = matched
        }

        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: filteredCalendars)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        if events.isEmpty {
            return "No events in the next \(daysAhead) day(s)."
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]

        let lines = events.map { event -> String in
            let start = formatter.string(from: event.startDate)
            let end = formatter.string(from: event.endDate)
            let cal = event.calendar?.title ?? "Unknown"
            let loc = event.location.map { " @ \($0)" } ?? ""
            return "- [\(cal)] \(event.title ?? "(untitled)")\(loc)\n  \(start) → \(end)"
        }

        return "Upcoming events (next \(daysAhead) days):\n\n" + lines.joined(separator: "\n\n")
    }
}
