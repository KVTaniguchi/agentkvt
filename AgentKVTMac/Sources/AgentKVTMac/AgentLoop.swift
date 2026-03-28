import Foundation

/// Runs one agent turn: send messages to LLM, handle tool calls, repeat until done.
public final class AgentLoop {
    public struct ToolBatchExecutionPolicy: Sendable {
        public let deferredToolResult: @Sendable (_ requestedToolName: String, _ batchToolNames: [String]) -> String?

        public init(
            deferredToolResult: @escaping @Sendable (_ requestedToolName: String, _ batchToolNames: [String]) -> String?
        ) {
            self.deferredToolResult = deferredToolResult
        }
    }

    public enum Event {
        case assistantResponse(content: String?, toolCalls: [OllamaClient.ToolCall])
        case toolCallRequested(name: String, arguments: String)
        case toolCallCompleted(name: String, result: String, wasDeferred: Bool)
        case finalResponse(String)
        case maxRoundsReached
    }

    private let client: any OllamaClientProtocol
    private let registry: ToolRegistry
    private let allowedToolIds: [String]
    private let toolBatchExecutionPolicy: ToolBatchExecutionPolicy?

    public init(
        client: any OllamaClientProtocol,
        registry: ToolRegistry,
        allowedToolIds: [String],
        toolBatchExecutionPolicy: ToolBatchExecutionPolicy? = nil
    ) {
        self.client = client
        self.registry = registry
        self.allowedToolIds = allowedToolIds
        self.toolBatchExecutionPolicy = toolBatchExecutionPolicy
    }

    /// Run until the model returns a message with no tool_calls (or max rounds).
    public func run(systemPrompt: String, userMessage: String, maxRounds: Int = 10, onEvent: ((Event) async -> Void)? = nil) async throws -> String {
        let messages: [OllamaClient.Message] = [
            .init(role: "system", content: systemPrompt, toolCalls: nil),
            .init(role: "user", content: userMessage, toolCalls: nil)
        ]
        return try await run(messages: messages, maxRounds: maxRounds, onEvent: onEvent)
    }

    /// Run until the model returns a message with no tool_calls (or max rounds) using a prebuilt conversation.
    public func run(messages initialMessages: [OllamaClient.Message], maxRounds: Int = 10, onEvent: ((Event) async -> Void)? = nil) async throws -> String {
        let tools = registry.ollamaToolDefs(allowedIds: allowedToolIds)
        var messages = initialMessages

        for _ in 0..<maxRounds {
            let response = try await client.chat(messages: messages, tools: tools.isEmpty ? nil : tools)
            guard let toolCalls = response.toolCalls, !toolCalls.isEmpty else {
                await onEvent?(.finalResponse(response.content ?? ""))
                return response.content ?? ""
            }
            await onEvent?(.assistantResponse(content: response.content, toolCalls: toolCalls))
            messages.append(.init(role: "assistant", content: response.content, toolCalls: toolCalls))
            let batchToolNames = toolCalls.compactMap { $0.function?.name }
            for tc in toolCalls {
                guard let fn = tc.function else { continue }
                await onEvent?(.toolCallRequested(name: fn.name, arguments: fn.arguments))
                let result: String
                let wasDeferred: Bool
                if let deferred = toolBatchExecutionPolicy?.deferredToolResult(fn.name, batchToolNames) {
                    result = deferred
                    wasDeferred = true
                } else {
                    do {
                        result = try await registry.execute(name: fn.name, arguments: fn.arguments, allowedIds: allowedToolIds)
                    } catch {
                        result = "Error: \(error)"
                    }
                    wasDeferred = false
                }
                await onEvent?(.toolCallCompleted(name: fn.name, result: result, wasDeferred: wasDeferred))
                messages.append(.init(role: "tool", content: result, toolCalls: nil, name: fn.name))
            }
        }
        await onEvent?(.maxRoundsReached)
        return "Max rounds reached."
    }
}
