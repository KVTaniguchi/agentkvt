import Foundation
import Testing
@testable import AgentKVTMac
@testable import ManagerCore

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

    @Test("daily mission is due after scheduled minute when it has not run yet")
    func dailyMissionDueAfterScheduledMinute() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let atEightOhFive = calendar.date(from: DateComponents(year: 2025, month: 3, day: 17, hour: 8, minute: 5))!
        let mission = MissionDefinition(
            missionName: "Daily",
            systemPrompt: "Prompt",
            triggerSchedule: "daily|08:00",
            allowedMCPTools: ["write_action_item"]
        )
        let scheduler = MissionScheduler(calendar: calendar, now: { atEightOhFive })
        #expect(scheduler.isDue(mission, at: atEightOhFive) == true)
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

    @Test("weekly mission is only due once per matching day")
    func weeklyMissionOnlyDueOncePerWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let mondayMorning = calendar.date(from: DateComponents(year: 2025, month: 3, day: 17, hour: 10, minute: 0))!
        let alreadyRan = calendar.date(from: DateComponents(year: 2025, month: 3, day: 17, hour: 8, minute: 0))!
        let mission = MissionDefinition(
            missionName: "Weekly",
            systemPrompt: "Prompt",
            triggerSchedule: "weekly|monday",
            allowedMCPTools: ["write_action_item"],
            lastRunAt: alreadyRan
        )
        let scheduler = MissionScheduler(calendar: calendar, now: { mondayMorning })
        #expect(scheduler.isDue(mission, at: mondayMorning) == false)
    }

    @Test("daily mission is not due again after it has already run in the window")
    func dailyMissionNotDueAfterAlreadyRunning() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let atEightOhFive = calendar.date(from: DateComponents(year: 2025, month: 3, day: 17, hour: 8, minute: 5))!
        let alreadyRan = calendar.date(from: DateComponents(year: 2025, month: 3, day: 17, hour: 8, minute: 1))!
        let mission = MissionDefinition(
            missionName: "Daily",
            systemPrompt: "Prompt",
            triggerSchedule: "daily|08:00",
            allowedMCPTools: ["write_action_item"],
            lastRunAt: alreadyRan
        )
        let scheduler = MissionScheduler(calendar: calendar, now: { atEightOhFive })
        #expect(scheduler.isDue(mission, at: atEightOhFive) == false)
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
