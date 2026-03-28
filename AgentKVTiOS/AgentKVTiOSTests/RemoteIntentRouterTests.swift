import Foundation
import Testing
@testable import AgentKVTiOS

// MARK: - Helpers

private func makeItem(
    systemIntent: String,
    payload: [String: IOSBackendJSONValue] = [:]
) -> IOSBackendActionItem {
    IOSBackendActionItem(
        id: UUID(),
        workspaceId: UUID(),
        sourceMissionId: nil,
        ownerProfileId: nil,
        title: "Test Action",
        systemIntent: systemIntent,
        payloadJson: payload,
        relevanceScore: 0.9,
        isHandled: false,
        handledAt: nil,
        timestamp: Date(),
        createdBy: "agent",
        createdAt: Date(),
        updatedAt: Date()
    )
}

// MARK: - Tests

@Suite("IntentRoute.route(for: IOSBackendActionItem)")
struct RemoteIntentRouterTests {

    @Test("calendar intent decodes eventTitle, startDate, durationMinutes, notes")
    func calendarIntent() {
        let item = makeItem(
            systemIntent: "calendar.create",
            payload: [
                "eventTitle":        .string("Dentist appointment"),
                "startDate":         .string("2026-04-01T09:00:00Z"),
                "durationMinutes":   .number(30),
                "notes":             .string("Bring insurance card")
            ]
        )
        let route = IntentRoute.route(for: item)
        guard case .calendar(let intent) = route else {
            Issue.record("Expected .calendar, got \(route)")
            return
        }
        #expect(intent.eventTitle == "Dentist appointment")
        #expect(intent.durationMinutes == 30)
        #expect(intent.notes == "Bring insurance card")
    }

    @Test("calendar intent falls back to item title when eventTitle missing")
    func calendarFallbackTitle() {
        let item = makeItem(systemIntent: "calendar.create")
        guard case .calendar(let intent) = IntentRoute.route(for: item) else {
            Issue.record("Expected .calendar")
            return
        }
        #expect(intent.eventTitle == "Test Action")
    }

    @Test("mailReply intent decodes toAddress, subject, draftBody")
    func mailReplyIntent() {
        let item = makeItem(
            systemIntent: "mail.reply",
            payload: [
                "toAddress":  .string("boss@example.com"),
                "subject":    .string("Re: Project Update"),
                "draftBody":  .string("Thanks for the update!")
            ]
        )
        guard case .mailReply(let intent) = IntentRoute.route(for: item) else {
            Issue.record("Expected .mailReply")
            return
        }
        #expect(intent.toAddress == "boss@example.com")
        #expect(intent.subject == "Re: Project Update")
        #expect(intent.draftBody == "Thanks for the update!")
    }

    @Test("reminder intent decodes reminderTitle, dueDate, notes")
    func reminderIntent() {
        let item = makeItem(
            systemIntent: "reminder.add",
            payload: [
                "reminderTitle": .string("Call accountant"),
                "dueDate":       .string("2026-04-15T17:00:00Z"),
                "notes":         .string("About Q1 taxes")
            ]
        )
        guard case .reminder(let intent) = IntentRoute.route(for: item) else {
            Issue.record("Expected .reminder")
            return
        }
        #expect(intent.reminderTitle == "Call accountant")
        #expect(intent.notes == "About Q1 taxes")
    }

    @Test("reminder intent has nil dueDate when key missing")
    func reminderNilDueDate() {
        let item = makeItem(
            systemIntent: "reminder.add",
            payload: ["reminderTitle": .string("Quick note")]
        )
        guard case .reminder(let intent) = IntentRoute.route(for: item) else {
            Issue.record("Expected .reminder")
            return
        }
        #expect(intent.dueDate == nil)
    }

    @Test("openURL intent decodes url and label")
    func openURLIntent() {
        let item = makeItem(
            systemIntent: "url.open",
            payload: [
                "url":   .string("https://example.com/jobs"),
                "label": .string("View Job Listing")
            ]
        )
        guard case .openURL(let intent) = IntentRoute.route(for: item) else {
            Issue.record("Expected .openURL")
            return
        }
        #expect(intent.targetURL.absoluteString == "https://example.com/jobs")
        #expect(intent.label == "View Job Listing")
    }

    @Test("openURL intent becomes unknown when url payload missing")
    func openURLMissingURL() {
        let item = makeItem(systemIntent: "url.open")  // no url key
        guard case .unknown = IntentRoute.route(for: item) else {
            Issue.record("Expected .unknown for missing url payload")
            return
        }
    }

    @Test("openURL intent becomes unknown when url is not a valid URL")
    func openURLInvalidURL() {
        let item = makeItem(
            systemIntent: "url.open",
            payload: ["url": .string("://bad url with spaces")]
        )
        guard case .unknown = IntentRoute.route(for: item) else {
            Issue.record("Expected .unknown for invalid url")
            return
        }
    }

    @Test("unrecognised system intent produces unknown route")
    func unknownIntent() {
        let item = makeItem(systemIntent: "something.new")
        guard case .unknown(let si) = IntentRoute.route(for: item) else {
            Issue.record("Expected .unknown")
            return
        }
        #expect(si == "something.new")
    }

    @Test("route metadata: calendar has correct icon and badge color")
    func calendarMetadata() {
        let route = IntentRoute.route(for: makeItem(
            systemIntent: "calendar.create",
            payload: ["eventTitle": .string("Meeting")]
        ))
        #expect(route.iconName == "calendar.badge.plus")
        #expect(route.label == "Add to Calendar")
    }

    @Test("route metadata: openURL label uses payload label field")
    func openURLLabel() {
        let item = makeItem(
            systemIntent: "url.open",
            payload: ["url": .string("https://example.com"), "label": .string("Open Report")]
        )
        #expect(IntentRoute.route(for: item).label == "Open Report")
    }

    @Test("route metadata: openURL without label falls back to 'Open Link'")
    func openURLDefaultLabel() {
        let item = makeItem(
            systemIntent: "url.open",
            payload: ["url": .string("https://example.com")]
        )
        #expect(IntentRoute.route(for: item).label == "Open Link")
    }
}
