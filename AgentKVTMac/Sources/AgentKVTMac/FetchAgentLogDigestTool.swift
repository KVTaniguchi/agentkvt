import Foundation
import ManagerCore

// MARK: - Factory function

public func makeFetchAgentLogDigestTool(backendClient: BackendAPIClient) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "fetch_agent_log_digest",
        name: "fetch_agent_log_digest",
        description: """
            Retrieve a high-level summary (digest) of recent agent execution logs. \
            Use this for a quick system health check, to see active objective IDs, \
            or to identify recurring errors without reading raw logs. Returns \
            aggregated counts by phase, a list of frequent errors/warnings, and \
            tool usage statistics. Extremely token-efficient for monitoring.
            """,
        parameters: .init(
            type: "object",
            properties: [
                "since_minutes": .init(
                    type: "integer",
                    description: "How far back to look in minutes. Default 120."
                )
            ],
            required: []
        ),
        handler: { args in
            let sinceMinutes = (args["since_minutes"] as? Int) ?? 120
            do {
                let digest = try await backendClient.fetchAgentLogDigest(sinceMinutes: sinceMinutes)
                return formatDigest(digest)
            } catch {
                return "Error fetching agent log digest: \(error)"
            }
        }
    )
}

// MARK: - Formatter

private func formatDigest(_ digest: BackendAgentLogDigest) -> String {
    var lines = ["=== Agent Log Digest (Last \(digest.windowMinutes) Min) ==="]
    lines.append("Total Entries: \(digest.totalEntries)")
    
    lines.append("\n--- Activity by Phase ---")
    if digest.byPhase.isEmpty {
        lines.append("(No activity documented)")
    } else {
        for (phase, count) in digest.byPhase.sorted(by: { $0.value > $1.value }) {
            lines.append("· \(phase): \(count)")
        }
    }
    
    if !digest.activeObjectiveIds.isEmpty {
        lines.append("\n--- Active Objectives ---")
        for id in digest.activeObjectiveIds {
            lines.append("· \(id)")
        }
    }
    
    if !digest.toolUsage.isEmpty {
        lines.append("\n--- Tool Usage Stats ---")
        for (tool, count) in digest.toolUsage.sorted(by: { $0.value > $1.value }) {
            lines.append("· \(tool): \(count) call(s)")
        }
    }
    
    lines.append("\n--- Recent Errors & Warnings ---")
    if digest.errors.isEmpty {
        lines.append("✅ No errors or warnings detected.")
    } else {
        for error in digest.errors {
            let latest = error.latestAt.map { " (latest: \($0))" } ?? ""
            lines.append("⚠ [\(error.phase)] x\(error.count): \(error.content)\(latest)")
        }
    }
    
    return lines.joined(separator: "\n")
}
