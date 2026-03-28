import AppIntents
import Foundation
import ManagerCore
import SwiftUI

// MARK: - Route

/// Typed representation of a decoded ActionItem intent + its fully-populated AppIntent.
///
/// Each case carries the concrete intent struct with all parameters already set from
/// the ActionItem's payloadData JSON so the caller can wire it directly into `Button(intent:)`.
enum IntentRoute {
    case calendar(CreateCalendarEventIntent)
    case mailReply(DraftMailReplyIntent)
    case reminder(AddReminderIntent)
    case openURL(OpenAgentURLIntent)
    case unknown(systemIntent: String)

    // MARK: Routing

    /// Decodes an ActionItem into a typed route.
    ///
    /// Returns `.unknown` for unrecognised `systemIntent` strings or when required
    /// payload keys are missing/malformed — the UI degrades gracefully rather than crashing.
    static func route(for item: ActionItem) -> IntentRoute {
        let payload = item.payloadData.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        } ?? [:]
        let normalizedIntent = SystemIntent.normalizedRawValue(from: item.systemIntent)

        return route(normalizedIntent: normalizedIntent, payload: payload, fallbackTitle: item.title, systemIntent: item.systemIntent)
    }

    /// Decodes a remote `IOSBackendActionItem` (fetched directly from Rails) into a typed route.
    static func route(for item: IOSBackendActionItem) -> IntentRoute {
        // Convert IOSBackendJSONValue to Foundation-native types so the shared helper's
        // `as? String` / `as? Int` casts work correctly. Numbers are stored as Double
        // internally; integer-valued doubles are converted back to Int.
        let payload: [String: Any] = item.payloadJson.reduce(into: [:]) { result, kv in
            switch kv.value {
            case .string(let s): result[kv.key] = s
            case .number(let n): result[kv.key] = n.truncatingRemainder(dividingBy: 1) == 0 ? Int(n) : n
            case .bool(let b):   result[kv.key] = b
            default:             break   // .null / .object / .array not used in intent payloads
            }
        }
        let normalizedIntent = SystemIntent.normalizedRawValue(from: item.systemIntent)
        return route(normalizedIntent: normalizedIntent, payload: payload, fallbackTitle: item.title, systemIntent: item.systemIntent)
    }

    private static func route(
        normalizedIntent: String,
        payload: [String: Any],
        fallbackTitle: String,
        systemIntent: String
    ) -> IntentRoute {

        switch normalizedIntent {

        case SystemIntent.calendarCreate.rawValue:
            let intent = CreateCalendarEventIntent()
            intent.eventTitle = payload["eventTitle"] as? String ?? fallbackTitle
            intent.startDate = (payload["startDate"] as? String).flatMap(parseISO8601) ?? Date()
            intent.durationMinutes = payload["durationMinutes"] as? Int ?? 60
            intent.notes = payload["notes"] as? String
            return .calendar(intent)

        case SystemIntent.mailReply.rawValue:
            let intent = DraftMailReplyIntent()
            intent.toAddress = payload["toAddress"] as? String ?? ""
            intent.subject = payload["subject"] as? String ?? fallbackTitle
            intent.draftBody = payload["draftBody"] as? String ?? ""
            return .mailReply(intent)

        case SystemIntent.reminderAdd.rawValue:
            let intent = AddReminderIntent()
            intent.reminderTitle = payload["reminderTitle"] as? String ?? fallbackTitle
            intent.dueDate = (payload["dueDate"] as? String).flatMap(parseISO8601)
            intent.notes = payload["notes"] as? String
            return .reminder(intent)

        case SystemIntent.urlOpen.rawValue:
            guard let rawURL = payload["url"] as? String, let url = URL(string: rawURL) else {
                return .unknown(systemIntent: systemIntent)
            }
            let intent = OpenAgentURLIntent()
            intent.targetURL = url
            intent.label = payload["label"] as? String
            return .openURL(intent)

        default:
            return .unknown(systemIntent: systemIntent)
        }
    }

    // MARK: Metadata

    var iconName: String {
        switch self {
        case .calendar:   return "calendar.badge.plus"
        case .mailReply:  return "envelope.badge"
        case .reminder:   return "bell.badge"
        case .openURL:    return "link"
        case .unknown:    return "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .calendar:              return "Add to Calendar"
        case .mailReply:             return "Draft Reply"
        case .reminder:              return "Add Reminder"
        case .openURL(let intent):   return intent.label ?? "Open Link"
        case .unknown(let si):       return si
        }
    }

    var badgeColor: Color {
        switch self {
        case .calendar:   return .blue
        case .mailReply:  return .indigo
        case .reminder:   return .orange
        case .openURL:    return .teal
        case .unknown:    return .gray
        }
    }
}

// MARK: - DynamicIntentButton

/// A SwiftUI button that drives the native iOS action for an ActionItem.
///
/// Uses typed `Button(intent:)` per route arm so the AppIntents runtime receives the
/// strongly-typed intent struct — required for system-sheet confirmation UI and Shortcuts
/// exposure. Falls back to a disabled row for unknown intents.
struct DynamicIntentButton: View {
    let item: ActionItem

    @Environment(\.openURL) private var openURL

    private var route: IntentRoute { IntentRoute.route(for: item) }


    var body: some View {
        switch route {
        case .calendar(let intent):
            Button(intent: intent) {
                intentLabel
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

        case .mailReply(let intent):
            Button(intent: intent) {
                intentLabel
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)

        case .reminder(let intent):
            Button(intent: intent) {
                intentLabel
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

        case .openURL(let intent):
            // Button(intent:) + OpensIntent silently no-ops when triggered in-app.
            // Use openURL environment action directly instead.
            Button {
                openURL(intent.targetURL)
            } label: {
                intentLabel
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)

        case .unknown(let si):
            HStack {
                Image(systemName: "questionmark.circle")
                Text(si)
                    .font(.footnote)
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var intentLabel: some View {
        Label(route.label, systemImage: route.iconName)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Remote variant (IOSBackendActionItem)

/// Same button logic as `DynamicIntentButton` but driven by a remote action item
/// fetched directly from the Rails backend (no SwiftData dependency).
struct RemoteDynamicIntentButton: View {
    let item: IOSBackendActionItem

    @Environment(\.openURL) private var openURL

    private var route: IntentRoute { IntentRoute.route(for: item) }

    var body: some View {
        switch route {
        case .calendar(let intent):
            Button(intent: intent) { intentLabel }
                .buttonStyle(.borderedProminent).tint(.blue)

        case .mailReply(let intent):
            Button(intent: intent) { intentLabel }
                .buttonStyle(.borderedProminent).tint(.indigo)

        case .reminder(let intent):
            Button(intent: intent) { intentLabel }
                .buttonStyle(.borderedProminent).tint(.orange)

        case .openURL(let intent):
            Button { openURL(intent.targetURL) } label: { intentLabel }
                .buttonStyle(.borderedProminent).tint(.teal)

        case .unknown(let si):
            HStack {
                Image(systemName: "questionmark.circle")
                Text(si).font(.footnote)
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var intentLabel: some View {
        Label(route.label, systemImage: route.iconName)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Helpers

private func parseISO8601(_ string: String) -> Date? {
    ISO8601DateFormatter().date(from: string)
}
