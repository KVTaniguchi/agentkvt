import Foundation
import ManagerCore

/// Implements OllamaClientProtocol backed by Gemini 2.0 Flash.
/// Used as a fallback when Ollama is unavailable or overloaded.
/// When tools are provided, uses ManualToolMode so Gemini responds with tool_calls JSON
/// that the AgentLoop can parse and dispatch exactly like Qwen's native tool responses.
public final class GeminiOllamaAdapter: OllamaClientProtocol, @unchecked Sendable {
    private let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public func chat(messages: [OllamaClient.Message], tools: [OllamaClient.ToolDef]?) async throws -> OllamaClient.Message {
        let hasTools = !(tools ?? []).isEmpty
        let messagesToSend = hasTools ? ManualToolMode.makeMessages(from: messages, tools: tools!) : messages
        let prompt = buildPrompt(from: messagesToSend)
        let raw = await GeminiTool.ask(question: prompt, apiKeyOverride: apiKey)
        return hasTools ? ManualToolMode.parseResponse(raw) : OllamaClient.Message(role: "assistant", content: raw)
    }

    private func buildPrompt(from messages: [OllamaClient.Message]) -> String {
        var parts: [String] = []
        for msg in messages {
            switch msg.role {
            case "system":
                if let content = msg.content, !content.isEmpty {
                    parts.append("Instructions:\n\(content)")
                }
            case "user":
                if let content = msg.content, !content.isEmpty {
                    parts.append("Task:\n\(content)")
                }
            case "assistant":
                if let content = msg.content, !content.isEmpty {
                    parts.append("Assistant:\n\(content)")
                } else if let calls = msg.toolCalls, !calls.isEmpty {
                    let summary = calls.compactMap { $0.function.map { "Called \($0.name)(\($0.arguments))" } }.joined(separator: "\n")
                    parts.append("Assistant:\n\(summary)")
                }
            case "tool":
                let name = msg.name ?? "tool"
                let content = msg.content ?? ""
                parts.append("Tool result [\(name)]:\n\(content)")
            default:
                if let content = msg.content, !content.isEmpty {
                    parts.append("\(msg.role):\n\(content)")
                }
            }
        }
        return parts.joined(separator: "\n\n")
    }
}
