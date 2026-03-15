import Foundation
import Testing
@testable import AgentKVTMac

struct MissionSchedulerTests {

    @Test("webhook schedule is never due by time")
    func webhookNeverDue() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let monday = calendar.date(from: DateComponents(year: 2025, month: 3, day: 17, hour: 9, minute: 0))!
        let scheduler = MissionScheduler(calendar: calendar, now: { monday })
        #expect(scheduler.isDue("webhook", at: monday) == false)
    }

    @Test("daily schedule is due when hour and minute match")
    func dailyDueWhenTimeMatches() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let atEight = calendar.date(from: DateComponents(year: 2025, month: 3, day: 17, hour: 8, minute: 0))!
        let scheduler = MissionScheduler(calendar: calendar, now: { atEight })
        #expect(scheduler.isDue("daily|08:00", at: atEight) == true)
    }

    @Test("daily schedule is not due when hour differs")
    func dailyNotDueWhenHourDiffers() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let atNine = calendar.date(from: DateComponents(year: 2025, month: 3, day: 17, hour: 9, minute: 0))!
        let scheduler = MissionScheduler(calendar: calendar, now: { atNine })
        #expect(scheduler.isDue("daily|08:00", at: atNine) == false)
    }

    @Test("weekly schedule is due on matching weekday")
    func weeklyDueOnMatchingWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        // March 17, 2025 is Monday
        let monday = calendar.date(from: DateComponents(year: 2025, month: 3, day: 17, hour: 10, minute: 0))!
        let scheduler = MissionScheduler(calendar: calendar, now: { monday })
        #expect(scheduler.isDue("weekly|monday", at: monday) == true)
    }

    @Test("weekly schedule is not due on other weekday")
    func weeklyNotDueOnOtherWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let tuesday = calendar.date(from: DateComponents(year: 2025, month: 3, day: 18, hour: 10, minute: 0))!
        let scheduler = MissionScheduler(calendar: calendar, now: { tuesday })
        #expect(scheduler.isDue("weekly|monday", at: tuesday) == false)
    }
}
