import SwiftUI
import SwiftData
import ManagerCore

/// Simple audit view: list recent AgentLog entries (reasoning, tool calls, outcomes).
struct AgentLogView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case tools = "Tools"
        case outcomes = "Outcomes"
        case issues = "Issues"

        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AgentLog.timestamp, order: .reverse) private var logs: [AgentLog]
    @State private var selectedFilter: Filter = .all

    private let backendSync = IOSBackendSyncService()

    private var filteredLogs: [AgentLog] {
        logs.filter { log in
            switch selectedFilter {
            case .all:
                return true
            case .tools:
                return log.phase == "tool_call" || log.phase == "tool_result"
            case .outcomes:
                return log.phase == "outcome" || log.phase == "assistant_final" || log.phase == "start"
            case .issues:
                return log.phase == "error" || log.phase == "warning"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(Filter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                List {
                    ForEach(filteredLogs.prefix(100), id: \.id) { log in
                        AgentLogRow(log: log)
                    }
                }
                .refreshable {
                    await backendSync.syncAgentLogs(modelContext: modelContext)
                }
                .emptyState(filteredLogs.isEmpty, message: emptyMessage)
            }
            .navigationTitle("Agent Log")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let runtimeLogURL = IOSRuntimeLog.availableLogFileURL {
                        ShareLink(item: runtimeLogURL) {
                            Label("Export runtime log", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .familyProfileToolbar()
        }
        .task {
            await backendSync.syncAgentLogs(modelContext: modelContext)
        }
    }

    private var emptyMessage: String {
        switch selectedFilter {
        case .all:
            return "No log entries yet. Missions write here when they run on the Mac."
        case .tools:
            return "No tool-call logs yet."
        case .outcomes:
            return "No mission lifecycle logs yet."
        case .issues:
            return "No warnings or errors logged."
        }
    }
}

private struct AgentLogRow: View {
    let log: AgentLog

    private var phaseColor: Color {
        switch log.phase {
        case "error":
            return .red
        case "warning":
            return .orange
        case "tool_call", "tool_result":
            return .blue
        case "outcome", "assistant_final":
            return .green
        default:
            return .secondary
        }
    }

    private var phaseLabel: String {
        log.phase.replacingOccurrences(of: "_", with: " ")
    }

    private var summaryText: String {
        switch log.phase {
        case "tool_call":
            if let toolName = log.toolName {
                return summarizeToolCall(named: toolName, raw: log.content)
            }
            return summarizeStructuredText(log.content)
        case "tool_result":
            if let toolName = log.toolName {
                return summarizeToolResult(named: toolName, raw: log.content)
            }
            return summarizeStructuredText(log.content)
        default:
            return summarizeStructuredText(log.content)
        }
    }

    private var rawDetailText: String? {
        let normalized = log.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized != summaryText.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return normalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(phaseLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(phaseColor.opacity(0.12))
                    .foregroundStyle(phaseColor)
                    .clipShape(Capsule())
                Spacer()
                Text(log.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let toolName = log.toolName {
                Label(toolName, systemImage: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(summaryText)
                .font(.body)
                .lineLimit(log.phase == "tool_call" ? 3 : 5)
            if let rawDetailText {
                DisclosureGroup("Raw detail") {
                    ScrollView(.horizontal) {
                        Text(rawDetailText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func summarizeToolCall(named toolName: String, raw: String) -> String {
        guard let json = parseJSONObject(from: raw) else {
            return "Requested \(toolName): \(summarizeStructuredText(raw))"
        }

        switch toolName {
        case "write_action_item":
            let title = (json["title"] as? String) ?? "Untitled action"
            let intent = (json["systemIntent"] as? String) ?? "unknown_intent"
            return "Create action item '\(title)' with intent '\(intent)'."
        case "send_notification_email":
            let subject = (json["subject"] as? String) ?? "(no subject)"
            return "Send notification email with subject '\(subject)'."
        case "github_agent":
            return "Run GitHub tool with \(json.keys.count) argument(s)."
        case "web_search_and_fetch":
            if let query = (json["query"] as? String) ?? (json["searchQuery"] as? String) {
                return "Search the web for '\(query)'."
            }
            return "Run web search."
        case "headless_browser_scout":
            if let url = json["url"] as? String {
                return "Inspect page at \(url)."
            }
            return "Inspect a web page with the browser scout."
        case "fetch_bee_ai_context":
            if let key = json["store_as_life_context_key"] as? String {
                return "Fetch Bee context and store it under '\(key)'."
            }
            return "Fetch Bee context."
        case "incoming_email_trigger":
            return "Fetch the next pending inbound email."
        default:
            return "Requested \(toolName) with \(json.keys.count) argument(s)."
        }
    }

    private func summarizeToolResult(named toolName: String, raw: String) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("Created ActionItem:") {
            return normalized
        }
        if normalized.hasPrefix("Error:") {
            return normalized
        }

        switch toolName {
        case "write_action_item":
            return normalized.isEmpty ? "Action item tool completed." : normalized
        case "send_notification_email":
            return normalized.isEmpty ? "Notification email tool completed." : normalized
        case "incoming_email_trigger":
            return normalized.isEmpty ? "Inbound email tool completed." : summarizeStructuredText(normalized)
        default:
            return summarizeStructuredText(normalized)
        }
    }

    private func summarizeStructuredText(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let json = parseJSONObject(from: normalized) {
            let pairs = json.keys.sorted().prefix(3).compactMap { key -> String? in
                guard let value = json[key] else { return nil }
                return "\(key): \(stringify(value))"
            }
            if !pairs.isEmpty {
                return pairs.joined(separator: " | ")
            }
        }

        let collapsed = normalized.replacingOccurrences(of: "\n", with: " ")
        if collapsed.count <= 180 {
            return collapsed
        }
        let index = collapsed.index(collapsed.startIndex, offsetBy: 177)
        return collapsed[..<index] + "..."
    }

    private func parseJSONObject(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func stringify(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let array as [Any]:
            return array.prefix(3).map(stringify).joined(separator: ", ")
        case let dict as [String: Any]:
            return dict.keys.sorted().prefix(3).joined(separator: ", ")
        default:
            return String(describing: value)
        }
    }
}
