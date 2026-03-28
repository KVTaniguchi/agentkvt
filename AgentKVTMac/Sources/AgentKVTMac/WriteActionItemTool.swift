import Foundation
import ManagerCore
import SwiftData

public protocol ActionItemWriting: Sendable {
    func createActionItem(
        title: String,
        systemIntent: String,
        payloadJson: String?
    ) async throws -> String
}

struct SwiftDataActionItemWriter: ActionItemWriting, @unchecked Sendable {
    let modelContext: ModelContext

    func createActionItem(
        title: String,
        systemIntent: String,
        payloadJson: String?
    ) async throws -> String {
        let missionId = MissionExecutionContext.current?.missionId
        let contentKey = Self.contentKey(systemIntent: systemIntent, payloadJson: payloadJson)

        // Dedup: skip if an identical unhandled action already exists for this mission.
        let descriptor = FetchDescriptor<ActionItem>(
            predicate: #Predicate<ActionItem> { !$0.isHandled }
        )
        if let existing = try? modelContext.fetch(descriptor) {
            let duplicate = existing.contains { item in
                guard item.missionId == missionId else { return false }
                let itemKey = Self.contentKey(
                    systemIntent: item.systemIntent,
                    payloadJson: item.payloadData.flatMap { String(data: $0, encoding: .utf8) }
                )
                return itemKey == contentKey
            }
            if duplicate {
                return "Skipped: identical unhandled action already exists — \(title.trimmingCharacters(in: .whitespacesAndNewlines)) (\(systemIntent))"
            }
        }

        let payloadData: Data? = payloadJson.flatMap { s in
            guard !s.isEmpty, let data = s.data(using: .utf8) else { return nil }
            return data
        }
        let item = ActionItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            systemIntent: systemIntent,
            payloadData: payloadData
        )
        item.missionId = missionId
        modelContext.insert(item)
        try modelContext.save()
        return "Created ActionItem: \(item.title) (\(item.systemIntent))"
    }

    /// Normalized content key used to detect duplicate actions.
    /// The payload is normalized by sorting keys so {"b":"2","a":"1"} == {"a":"1","b":"2"}.
    private static func contentKey(systemIntent: String, payloadJson: String?) -> String {
        let normalizedPayload: String
        if let json = payloadJson,
           !json.isEmpty,
           let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            normalizedPayload = obj.keys.sorted().map { "\($0)=\(obj[$0] ?? "")" }.joined(separator: ",")
        } else {
            normalizedPayload = ""
        }
        return "\(systemIntent)|\(normalizedPayload)"
    }
}

struct BackendActionItemWriter: ActionItemWriting {
    let backendClient: BackendAPIClient

    func createActionItem(
        title: String,
        systemIntent: String,
        payloadJson: String?
    ) async throws -> String {
        guard let missionId = MissionExecutionContext.current?.missionId else {
            return "Error: write_action_item requires an active mission context in backend mode."
        }
        let item = try await backendClient.createActionItem(
            missionId: missionId,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            systemIntent: systemIntent,
            payloadJson: payloadJson
        )
        return "Created ActionItem: \(item.title) (\(item.systemIntent))"
    }
}

/// MCP-style tool that writes a single ActionItem to the shared store.
/// Only title and systemIntent are taken from LLM; payloadData is optional and validated.
public func makeWriteActionItemTool(actionItemWriter: any ActionItemWriting) -> ToolRegistry.Tool {
    let payloadDescription: String = SystemIntent.allCases.map { intent in
        let fields = intent.payloadFields.map { f in
            "\(f.key): \(f.valueType)\(f.required ? "" : " (optional)")"
        }.joined(separator: ", ")
        return "\(intent.rawValue) → {\(fields)}"
    }.joined(separator: "; ")

    return ToolRegistry.Tool(
        id: "write_action_item",
        name: "write_action_item",
        description: "Write a dynamic action item (button) for the iOS dashboard. Call this tool whenever the mission needs a visible user-facing result, recommendation, or report. Most missions that produce something for the user should end by calling this tool. Choose the systemIntent that best fits the output, then populate payloadJson with the required fields for that intent. Prefer systemIntent url.open when you found a concrete link the user should review.",
        parameters: .init(
            type: "object",
            properties: [
                "title": .init(type: "string", description: "Short button label describing the outcome for the user."),
                "systemIntent": .init(
                    type: "string",
                    description: "Intent identifier for the button. Determines which native iOS action is triggered.",
                    enumValues: SystemIntent.allCases.map(\.rawValue)
                ),
                "payloadJson": .init(type: "string", description: "JSON object string with intent-specific fields. \(payloadDescription)")
            ],
            required: ["title", "systemIntent"]
        ),
        handler: { args in
            guard let title = args["title"] as? String, !title.isEmpty,
                  let systemIntent = args["systemIntent"] as? String, !systemIntent.isEmpty else {
                return "Error: title and systemIntent are required non-empty strings."
            }
            let normalizedSystemIntent = SystemIntent.normalizedRawValue(from: systemIntent)
            guard SystemIntent(rawValue: normalizedSystemIntent) != nil else {
                let allowed = SystemIntent.allCases.map(\.rawValue).joined(separator: ", ")
                return "Error: systemIntent must be one of [\(allowed)]."
            }
            return try await actionItemWriter.createActionItem(
                title: title,
                systemIntent: normalizedSystemIntent,
                payloadJson: args["payloadJson"] as? String
            )
        }
    )
}

public func makeWriteActionItemTool(modelContext: ModelContext) -> ToolRegistry.Tool {
    makeWriteActionItemTool(actionItemWriter: SwiftDataActionItemWriter(modelContext: modelContext))
}

public func makeWriteActionItemTool(backendClient: BackendAPIClient) -> ToolRegistry.Tool {
    makeWriteActionItemTool(actionItemWriter: BackendActionItemWriter(backendClient: backendClient))
}
