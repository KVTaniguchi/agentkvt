import Foundation
import ManagerCore
import SwiftData

/// Read-only MCP tool that summarizes mission state and recent execution activity.
public func makeFetchMissionStatusTool(modelContext: ModelContext) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "fetch_mission_status",
        name: "fetch_mission_status",
        description: """
            Retrieve mission status from shared SwiftData. Use this when a user asks what the Mac \
            agent is currently doing, whether a mission ran recently, or whether any mission failed.
            """,
        parameters: .init(
            type: "object",
            properties: [
                "mission_name": .init(
                    type: "string",
                    description: "Optional case-insensitive substring filter for a specific mission name."
                ),
                "include_recent_logs": .init(
                    type: "boolean",
                    description: "Optional. Include the latest execution log lines for each mission. Defaults to true."
                ),
                "limit": .init(
                    type: "integer",
                    description: "Optional. Max missions to return (1-10). Defaults to 5."
                ),
            ],
            required: []
        ),
        handler: { args in
            await MissionStatusToolHandler.fetch(modelContext: modelContext, args: args)
        }
    )
}

enum MissionStatusToolHandler {
    static func fetch(modelContext: ModelContext, args: [String: Any]) async -> String {
        let missionNameFilter = (args["mission_name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let includeRecentLogs = (args["include_recent_logs"] as? Bool) ?? true
        let rawLimit = (args["limit"] as? Int) ?? ((args["limit"] as? Double).map(Int.init) ?? 5)
        let limit = min(max(rawLimit, 1), 10)

        do {
            let missionDescriptor = FetchDescriptor<MissionDefinition>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            let allMissions = try modelContext.fetch(missionDescriptor)
            let filtered = allMissions.filter { mission in
                guard let missionNameFilter, !missionNameFilter.isEmpty else { return true }
                return mission.missionName.localizedCaseInsensitiveContains(missionNameFilter)
            }

            guard !filtered.isEmpty else {
                if let missionNameFilter, !missionNameFilter.isEmpty {
                    return "No missions match '\(missionNameFilter)'."
                }
                return "No missions found."
            }

            let selected = Array(filtered.prefix(limit))
            let logDescriptor = FetchDescriptor<AgentLog>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            let allLogs = try modelContext.fetch(logDescriptor)

            return selected.map { mission in
                renderMissionStatus(
                    mission,
                    logs: matchingLogs(for: mission, in: allLogs),
                    includeRecentLogs: includeRecentLogs
                )
            }.joined(separator: "\n\n---\n\n")
        } catch {
            return "Error retrieving mission status: \(error)"
        }
    }

    private static func matchingLogs(for mission: MissionDefinition, in logs: [AgentLog]) -> [AgentLog] {
        logs.filter { log in
            if let missionId = log.missionId {
                return missionId == mission.id
            }
            if let missionName = log.missionName {
                return missionName == mission.missionName
            }
            return false
        }
    }

    private static func renderMissionStatus(
        _ mission: MissionDefinition,
        logs: [AgentLog],
        includeRecentLogs: Bool
    ) -> String {
        var lines: [String] = [
            "Mission: \(mission.missionName)",
            "Enabled: \(mission.isEnabled ? "yes" : "no")",
            "Trigger: \(mission.triggerSchedule)",
            "Last run: \(mission.lastRunAt.map(format(date:)) ?? "never")",
            "Updated: \(format(date: mission.updatedAt))",
            "Status summary: \(statusSummary(for: mission, logs: logs))",
        ]

        guard includeRecentLogs else {
            return lines.joined(separator: "\n")
        }

        let recentLogs = Array(logs.prefix(3))
        if recentLogs.isEmpty {
            lines.append("Recent logs: none")
            return lines.joined(separator: "\n")
        }

        lines.append("Recent logs:")
        for log in recentLogs {
            let missionScopedName = log.toolName.map { " [\($0)]" } ?? ""
            lines.append("- \(format(date: log.timestamp)) | \(log.phase)\(missionScopedName): \(truncate(log.content))")
        }
        return lines.joined(separator: "\n")
    }

    private static func statusSummary(for mission: MissionDefinition, logs: [AgentLog]) -> String {
        guard mission.isEnabled else {
            return "Disabled."
        }
        guard let latestLog = logs.first else {
            return mission.lastRunAt == nil ? "Enabled, waiting for first run." : "Enabled, no recent log details."
        }

        switch latestLog.phase {
        case "error":
            return "Latest run hit an error."
        case "warning":
            return "Latest run reported a warning."
        case "outcome", "assistant_final", "chat_outcome":
            return "Latest run completed successfully."
        case "tool_call", "tool_result":
            return "Mission was recently active and using tools."
        case "start":
            return "Mission started recently."
        default:
            return "Latest activity phase: \(latestLog.phase)."
        }
    }

    private static func format(date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func truncate(_ text: String, maxLength: Int = 180) -> String {
        let compact = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > maxLength else { return compact }
        return String(compact.prefix(maxLength - 1)) + "…"
    }
}
