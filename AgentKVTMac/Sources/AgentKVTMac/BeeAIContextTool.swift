import Foundation
import ManagerCore
import SwiftData

/// MCP tool: fetch personal context from a Bee-compatible HTTP API (see Bee docs:
/// https://docs.bee.computer/docs/proxy — typically `bee proxy` on localhost).
/// Summaries go to LifeContext or AgentLog. Default path `v1/insights` is legacy until
/// responses match official Bee `/v1/*` JSON (see Docs/BEE_AI_INTEGRATION_PLAN.md).
public func makeFetchBeeAIContextTool(modelContext: ModelContext) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "fetch_bee_ai_context",
        name: "fetch_bee_ai_context",
        description: "Fetch personal context from the Bee HTTP API (typically local bee proxy). Use to ground missions on recent conversations, daily briefs, or notes. Results are stored in LifeContext or AgentLog.",
        parameters: .init(
            type: "object",
            properties: [
                "store_as_life_context_key": .init(type: "string", description: "Optional. If set, store the summary in LifeContext under this key (e.g. 'bee_ai_recent'). Omit to only log to AgentLog.")
            ],
            required: []
        ),
        handler: { args in
            let lifeContextKey = args["store_as_life_context_key"] as? String
            return await BeeAIContextTool.fetchAndStore(modelContext: modelContext, storeAsLifeContextKey: lifeContextKey)
        }
    )
}

enum BeeAIContextTool {
    static func fetchAndStore(modelContext: ModelContext, storeAsLifeContextKey lifeContextKey: String?) async -> String {
        // Test hook: when set, use canned JSON instead of HTTP (for integration tests).
        if let mockJson = ProcessInfo.processInfo.environment["MOCK_BEE_AI_RESPONSE_JSON"],
           let data = mockJson.data(using: .utf8) {
            return processBeeAIResponse(data: data, modelContext: modelContext, lifeContextKey: lifeContextKey)
        }
        guard let baseURLString = ProcessInfo.processInfo.environment["BEE_AI_BASE_URL"] ?? ProcessInfo.processInfo.environment["BEE_AI_API_URL"],
              let baseURL = URL(string: baseURLString),
              let apiKey = ProcessInfo.processInfo.environment["BEE_AI_API_KEY"], !apiKey.isEmpty else {
            return "Error: BEE_AI_BASE_URL (or BEE_AI_API_URL) and BEE_AI_API_KEY must be set."
        }
        let path = ProcessInfo.processInfo.environment["BEE_AI_INSIGHTS_PATH"] ?? "v1/insights"
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "Error: invalid response." }
            guard http.statusCode == 200 else {
                return "Bee API error: status \(http.statusCode). Check base URL and API key."
            }
            return processBeeAIResponse(data: data, modelContext: modelContext, lifeContextKey: lifeContextKey)
        } catch {
            return "Error fetching Bee API: \(error)"
        }
    }

    private static func processBeeAIResponse(data: Data, modelContext: ModelContext, lifeContextKey: String?) -> String {
        let summary = parseAndSummarize(data: data)
        let log = AgentLog(missionId: nil, missionName: nil, phase: "bee_ai_fetch", content: summary, toolName: "fetch_bee_ai_context")
        modelContext.insert(log)
        if let key = lifeContextKey, !key.isEmpty {
            let descriptor = FetchDescriptor<LifeContext>(predicate: #Predicate { $0.key == key })
            let existing = try? modelContext.fetch(descriptor)
            if let first = existing?.first {
                first.value = summary
                first.updatedAt = Date()
            } else {
                let ctx = LifeContext(key: key, value: summary)
                modelContext.insert(ctx)
            }
        }
        try? modelContext.save()
        return "Stored Bee context. Summary: \(summary.prefix(500))\(summary.count > 500 ? "…" : "")."
    }

    private static func parseAndSummarize(data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Raw response (no JSON): \(data.count) bytes."
        }
        var parts: [String] = []
        if let insights = json["insights"] as? [[String: Any]] {
            for (i, item) in insights.prefix(20).enumerated() {
                parts.append(formatInsight(item, index: i + 1))
            }
        }
        if let transcriptions = json["transcriptions"] as? [[String: Any]] {
            for (i, item) in transcriptions.prefix(20).enumerated() {
                parts.append(formatTranscription(item, index: i + 1))
            }
        }
        if let items = json["data"] as? [[String: Any]] {
            for (i, item) in items.prefix(20).enumerated() {
                parts.append(formatInsight(item, index: i + 1))
            }
        }
        if parts.isEmpty {
            return "No insights or transcriptions in response. Keys: \(json.keys.joined(separator: ", "))."
        }
            return "Bee context (recent):\n" + parts.joined(separator: "\n")
    }

    private static func formatInsight(_ item: [String: Any], index: Int) -> String {
        let text = item["text"] as? String ?? item["content"] as? String ?? item["summary"] as? String ?? "?"
        let ts = item["timestamp"] as? String ?? item["created_at"] as? String ?? ""
        return "[\(index)] \(ts.isEmpty ? "" : "\(ts) ")\(text)"
    }

    private static func formatTranscription(_ item: [String: Any], index: Int) -> String {
        let text = item["text"] as? String ?? item["content"] as? String ?? "?"
        let ts = item["timestamp"] as? String ?? item["start_time"] as? String ?? ""
        return "[\(index)] \(ts.isEmpty ? "" : "\(ts) ")\(text)"
    }
}
