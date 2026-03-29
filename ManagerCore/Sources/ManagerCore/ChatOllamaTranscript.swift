import Foundation

/// Builds a plain Ollama `/api/chat` message list for direct (non-tool) completion on iOS.
public enum ChatOllamaTranscript {
    /// Excludes failed bubbles; includes user and assistant rows in timestamp order after the system prompt.
    public static func messagesForAPI(systemPrompt: String, threadMessages: [ChatMessage]) -> [OllamaClient.Message] {
        var out: [OllamaClient.Message] = [
            .init(role: "system", content: systemPrompt, toolCalls: nil)
        ]
        let sorted = threadMessages.sorted { $0.timestamp < $1.timestamp }
        for m in sorted {
            guard m.status != ChatMessageStatus.failed.rawValue else { continue }
            if m.role == "user" || m.role == "assistant" {
                out.append(.init(role: m.role, content: m.content, toolCalls: nil))
            }
        }
        return out
    }
}
