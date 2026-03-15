import Foundation
import ManagerCore

/// CRON-style scheduler: determines which missions are due at a given time based on triggerSchedule.
/// Schedule format: "daily|HH:mm", "weekly|weekday", "webhook" (webhook = only when triggered externally).
public struct MissionScheduler {
    private let calendar: Calendar
    private let now: () -> Date

    public init(calendar: Calendar = .current, now: @escaping () -> Date = { Date() }) {
        self.calendar = calendar
        self.now = now
    }

    /// Returns missions that are due at the current time (and enabled).
    public func dueMissions(from missions: [MissionDefinition]) -> [MissionDefinition] {
        let date = now()
        return missions.filter { mission in
            mission.isEnabled && isDue(mission.triggerSchedule, at: date)
        }
    }

    /// Parse triggerSchedule and check if it's due at the given date.
    /// - "daily|08:00" -> due if current time is within the same hour (or we could do "within last run window")
    /// - "weekly|monday" -> due on that weekday (e.g. once per week)
    /// - "webhook" -> never due by time (only when explicitly triggered)
    /// For simplicity: daily = due if we're past the time today and haven't run (caller tracks last run); we just say "is this the right time?"
    /// Simplified: daily|08:00 = due when hour is 8 and minute >= 0; weekly|monday = due when weekday is monday. No last-run tracking here.
    public func isDue(_ schedule: String, at date: Date) -> Bool {
        let parts = schedule.split(separator: "|", maxSplits: 1).map(String.init)
        guard let kind = parts.first?.lowercased() else { return false }
        switch kind {
        case "webhook":
            return false
        case "daily":
            guard parts.count == 2 else { return false }
            let timePart = parts[1]
            let hourMin = timePart.split(separator: ":")
            guard hourMin.count >= 1,
                  let h = Int(hourMin[0]),
                  (0..<24).contains(h) else { return false }
            let m = hourMin.count > 1 ? (Int(hourMin[1]) ?? 0) : 0
            let comp = calendar.dateComponents([.hour, .minute], from: date)
            return comp.hour == h && (comp.minute ?? 0) == m
        case "weekly":
            guard parts.count == 2 else { return false }
            let weekdayStr = parts[1].lowercased()
            let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            guard let idx = weekdays.firstIndex(of: weekdayStr) else { return false }
            let comp = calendar.dateComponents([.weekday], from: date)
            return comp.weekday == idx + 1
        default:
            return false
        }
    }
}
