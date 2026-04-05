import Foundation
import ManagerCore
import SwiftData

// MARK: - Factory functions

public func makeFetchAgentLogsTool(modelContext: ModelContext) -> ToolRegistry.Tool {
    makeAgentLogsTool { args in
        await FetchAgentLogsHandler.fetchLocal(modelContext: modelContext, args: args)
    }
}

public func makeFetchAgentLogsTool(backendClient: BackendAPIClient) -> ToolRegistry.Tool {
    makeAgentLogsTool { args in
        await FetchAgentLogsHandler.fetchRemote(backendClient: backendClient, args: args)
    }
}

private func makeAgentLogsTool(handler: @escaping ([String: Any]) async -> String) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "fetch_agent_logs",
        name: "fetch_agent_logs",
        description: """
            Retrieve and analyze recent agent execution logs. Use this to diagnose \
            failures, detect repeated errors, inspect which tools were called and what they \
            returned, or understand why an action produced unexpected output. Returns \
            timestamped log entries with phase labels (start, tool_call, \
            tool_result, error, warning, outcome).
            """,
        parameters: .init(
            type: "object",
            properties: [
                "phases": .init(
                    type: "string",
                    description: "Optional comma-separated list of phases to include, e.g. \"error,warning,outcome\". Omit to include all phases."
                ),
                "limit": .init(
                    type: "integer",
                    description: "Max log entries to return. Default 100, max 200."
                ),
                "since_minutes": .init(
                    type: "integer",
                    description: "How far back to look in minutes. Default 120."
                )
            ],
            required: []
        ),
        handler: { args in await handler(args) }
    )
}

// MARK: - Handler

enum FetchAgentLogsHandler {

    struct LogEntry {
        let timestamp: Date
        let phase: String
        let toolName: String?
        let content: String
    }

    // MARK: Local (SwiftData)

    static func fetchLocal(modelContext: ModelContext, args: [String: Any]) async -> String {
        let phases = parsePhasesArg(args["phases"])
        let limit = parseLimit(args["limit"])
        let sinceMinutes = parseSinceMinutes(args["since_minutes"])
        let since = Date().addingTimeInterval(-Double(sinceMinutes) * 60)

        do {
            let descriptor = FetchDescriptor<AgentLog>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            let allLogs = try modelContext.fetch(descriptor)
            let filtered = allLogs.filter { log in
                guard log.timestamp >= since else { return false }
                if !phases.isEmpty {
                    guard phases.contains(log.phase) else { return false }
                }
                return true
            }
            let entries = Array(filtered.prefix(limit)).map {
                LogEntry(timestamp: $0.timestamp, phase: $0.phase, toolName: $0.toolName, content: $0.content)
            }
            return format(logs: entries, sinceMinutes: sinceMinutes)
        } catch {
            return "Error reading local agent logs: \(error)"
        }
    }

    // MARK: Remote (backend)

    static func fetchRemote(backendClient: BackendAPIClient, args: [String: Any]) async -> String {
        let phases = parsePhasesArg(args["phases"])
        let limit = parseLimit(args["limit"])
        let sinceMinutes = parseSinceMinutes(args["since_minutes"])
        let since = Date().addingTimeInterval(-Double(sinceMinutes) * 60)

        do {
            let logs = try await backendClient.fetchAgentLogs(limit: limit)
            var entries = logs
                .filter { $0.timestamp >= since }
                .map { log in
                    LogEntry(
                        timestamp: log.timestamp,
                        phase: log.phase,
                        toolName: log.metadataJson["tool_name"],
                        content: log.content
                    )
                }
            if !phases.isEmpty {
                entries = entries.filter { phases.contains($0.phase) }
            }
            return format(logs: Array(entries.prefix(limit)), sinceMinutes: sinceMinutes)
        } catch {
            return "Error fetching agent logs: \(error)"
        }
    }

    // MARK: - Output formatting

    static func format(logs: [LogEntry], sinceMinutes: Int) -> String {
        guard !logs.isEmpty else {
            return "No agent log entries found in the last \(sinceMinutes) minutes."
        }

        let header = "=== Agent Log Analysis ===\nWindow: last \(sinceMinutes) min | \(logs.count) total entries"
        let errorCount = logs.filter { $0.phase == "error" }.count
        let warningCount = logs.filter { $0.phase == "warning" }.count

        var lines = ["--- Execution Logs (\(logs.count) entries) ---"]
        if errorCount > 0 || warningCount > 0 {
            let parts = [errorCount > 0 ? "\(errorCount) error(s)" : nil,
                         warningCount > 0 ? "\(warningCount) warning(s)" : nil]
                .compactMap { $0 }.joined(separator: " · ")
            lines.append("⚠ \(parts)")
        }

        for entry in logs.sorted(by: { $0.timestamp < $1.timestamp }) {
            let toolLabel = entry.toolName.map { name in " [\(name)]" } ?? ""
            lines.append("[\(timeString(entry.timestamp)) \(entry.phase)\(toolLabel)] \(truncate(entry.content))")
        }

        let section = lines.joined(separator: "\n")
        return [header, section].joined(separator: "\n\n")
    }

    // MARK: - Argument parsing helpers

    private static func parsePhasesArg(_ value: Any?) -> [String] {
        guard let str = value as? String, !str.isEmpty else { return [] }
        return str.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseLimit(_ value: Any?) -> Int {
        let raw: Int
        if let i = value as? Int { raw = i }
        else if let d = value as? Double { raw = Int(d) }
        else { raw = 100 }
        return min(max(raw, 1), 200)
    }

    private static func parseSinceMinutes(_ value: Any?) -> Int {
        let raw: Int
        if let i = value as? Int { raw = i }
        else if let d = value as? Double { raw = Int(d) }
        else { raw = 120 }
        return max(raw, 1)
    }

    private static func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private static func truncate(_ text: String, maxLength: Int = 200) -> String {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > maxLength else { return compact }
        return String(compact.prefix(maxLength - 1)) + "…"
    }
}
