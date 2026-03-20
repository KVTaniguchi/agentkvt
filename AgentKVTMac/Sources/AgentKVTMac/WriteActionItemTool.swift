import Foundation
import ManagerCore
import SwiftData

/// MCP-style tool that writes a single ActionItem to the shared store.
/// Only title and systemIntent are taken from LLM; payloadData is optional and validated.
public func makeWriteActionItemTool(modelContext: ModelContext) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "write_action_item",
        name: "write_action_item",
        description: "Write a dynamic action item (button) for the iOS dashboard. Use this to present a result or recommendation to the user.",
        parameters: .init(
            type: "object",
            properties: [
                "title": .init(type: "string", description: "Short button label, e.g. 'Review New Job Leads'"),
                "systemIntent": .init(type: "string", description: "Intent identifier for the button"),
                "payloadJson": .init(type: "string", description: "Optional JSON string payload; omit or empty if not needed")
            ],
            required: ["title", "systemIntent"]
        ),
        handler: { args in
            guard let title = args["title"] as? String, !title.isEmpty,
                  let systemIntent = args["systemIntent"] as? String, !systemIntent.isEmpty else {
                return "Error: title and systemIntent are required non-empty strings."
            }
            let payloadData: Data? = (args["payloadJson"] as? String).flatMap { s in
                guard !s.isEmpty, let d = s.data(using: .utf8) else { return nil }
                return d
            }
            let item = ActionItem(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                systemIntent: systemIntent.trimmingCharacters(in: .whitespacesAndNewlines),
                payloadData: payloadData
            )
            item.missionId = MissionExecutionContext.current?.missionId
            modelContext.insert(item)
            try modelContext.save()
            return "Created ActionItem: \(item.title) (\(item.systemIntent))"
        }
    )
}
