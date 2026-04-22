import Foundation
import ManagerCore

/// Implements OllamaClientProtocol backed by Gemini 2.0 Flash.
/// Used as a fallback when Ollama is unavailable or overloaded.
/// Does not support tool-calling — returns text-only responses.
public final class GeminiOllamaAdapter: OllamaClientProtocol, @unchecked Sendable {
    private let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public func chat(messages: [OllamaClient.Message], tools: [OllamaClient.ToolDef]?) async throws -> OllamaClient.Message {
        let prompt = buildPrompt(from: messages)
        let answer = await GeminiTool.ask(question: prompt, apiKeyOverride: apiKey)
        return OllamaClient.Message(role: "assistant", content: answer)
    }

    private func buildPrompt(from messages: [OllamaClient.Message]) -> String {
        var parts: [String] = []
        for msg in messages {
            guard let content = msg.content, !content.isEmpty else { continue }
            switch msg.role {
            case "system": parts.append("Instructions:\n\(content)")
            case "user":   parts.append("Task:\n\(content)")
            default: break
            }
        }
        return parts.joined(separator: "\n\n")
    }
}
