import Foundation

/// Zero-trust tool registry: each tool has a stable ID, JSON schema, and a handler that validates/sanitizes arguments.
public final class ToolRegistry {
    public typealias ToolHandler = ([String: Any]) async throws -> String

    public struct Tool {
        public let id: String
        public let name: String
        public let description: String?
        public let parameters: OllamaClient.ToolDef.JSONSchema?
        public let handler: ToolHandler

        public init(id: String, name: String, description: String?, parameters: OllamaClient.ToolDef.JSONSchema?, handler: @escaping ToolHandler) {
            self.id = id
            self.name = name
            self.description = description
            self.parameters = parameters
            self.handler = handler
        }
    }

    private var tools: [String: Tool] = [:]
    private let queue = DispatchQueue(label: "ToolRegistry")

    public init() {}

    public func register(_ tool: Tool) {
        queue.sync { tools[tool.id] = tool }
    }

    public func tool(id: String) -> Tool? {
        queue.sync { tools[id] }
    }

    public func toolIds() -> [String] {
        queue.sync { Array(tools.keys).sorted() }
    }

    /// Returns Ollama-format tool definitions for the given allowed IDs.
    public func ollamaToolDefs(allowedIds: [String]) -> [OllamaClient.ToolDef] {
        queue.sync {
            allowedIds.compactMap { id in
                tools[id].map { t in
                    OllamaClient.ToolDef(function: .init(name: t.name, description: t.description, parameters: t.parameters))
                }
            }
        }
    }

    /// Execute a tool by name (as returned by the LLM) with raw arguments. Validates and runs only if allowed.
    public func execute(name: String, arguments: String, allowedIds: [String]) async throws -> String {
        guard let tool = queue.sync(execute: { tools.values.first { $0.name == name } }) else {
            throw ToolRegistryError.unknownTool(name)
        }
        guard allowedIds.contains(tool.id) else {
            throw ToolRegistryError.toolNotAllowed(tool.id)
        }
        let args = parseArguments(arguments)
        return try await tool.handler(args)
    }

    private func parseArguments(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }
}

public enum ToolRegistryError: Error {
    case unknownTool(String)
    case toolNotAllowed(String)
}
