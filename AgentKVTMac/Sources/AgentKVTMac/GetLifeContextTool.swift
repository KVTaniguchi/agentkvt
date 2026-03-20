import Foundation
import ManagerCore
import SwiftData

/// MCP tool: fetch life context facts from the shared SwiftData store.
public func makeGetLifeContextTool(modelContext: ModelContext) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "get_life_context",
        name: "get_life_context",
        description: "Retrieve specific user context (like goals, relationships, or location) stored in the LifeContext database. Input can be a specific key, or empty to list all available keys.",
        parameters: .init(
            type: "object",
            properties: [
                "key": .init(type: "string", description: "Optional. The specific LifeContext key to fetch (e.g. 'goals'). Omit to list all available keys.")
            ],
            required: []
        ),
        handler: { args in
            let key = args["key"] as? String
            return await GetLifeContextToolHandler.fetch(modelContext: modelContext, key: key)
        }
    )
}

enum GetLifeContextToolHandler {
    static func fetch(modelContext: ModelContext, key: String?) async -> String {
        do {
            if let targetKey = key, !targetKey.isEmpty {
                let descriptor = FetchDescriptor<LifeContext>()
                let results = try modelContext.fetch(descriptor)
                if let first = results.first(where: { $0.key == targetKey }) {
                    return "LifeContext [\(targetKey)]: \(first.value)"
                } else {
                    return "LifeContext key '\(targetKey)' not found."
                }
            } else {
                let descriptor = FetchDescriptor<LifeContext>()
                let results = try modelContext.fetch(descriptor)
                if results.isEmpty {
                    return "No LifeContext entries found."
                }
                let keys = results.map { $0.key }.joined(separator: ", ")
                return "Available LifeContext keys: \(keys)"
            }
        } catch {
            return "Error retrieving LifeContext: \(error)"
        }
    }
}
