import Foundation

/// Runs one agent turn: send messages to LLM, handle tool calls, repeat until done.
public final class AgentLoop {
    private let client: any OllamaClientProtocol
    private let registry: ToolRegistry
    private let allowedToolIds: [String]

    public init(client: any OllamaClientProtocol, registry: ToolRegistry, allowedToolIds: [String]) {
        self.client = client
        self.registry = registry
        self.allowedToolIds = allowedToolIds
    }

    /// Run until the model returns a message with no tool_calls (or max rounds).
    public func run(systemPrompt: String, userMessage: String, maxRounds: Int = 10) async throws -> String {
        let tools = registry.ollamaToolDefs(allowedIds: allowedToolIds)
        var messages: [OllamaClient.Message] = [
            .init(role: "system", content: systemPrompt, toolCalls: nil),
            .init(role: "user", content: userMessage, toolCalls: nil)
        ]

        for _ in 0..<maxRounds {
            let response = try await client.chat(messages: messages, tools: tools.isEmpty ? nil : tools)
            guard let toolCalls = response.toolCalls, !toolCalls.isEmpty else {
                return response.content ?? ""
            }
            messages.append(.init(role: "assistant", content: response.content, toolCalls: toolCalls))
            for tc in toolCalls {
                guard let fn = tc.function else { continue }
                let result: String
                do {
                    result = try await registry.execute(name: fn.name, arguments: fn.arguments, allowedIds: allowedToolIds)
                } catch {
                    result = "Error: \(error)"
                }
                messages.append(.init(role: "tool", content: result, toolCalls: nil, name: fn.name))
            }
        }
        return "Max rounds reached."
    }
}
