import Foundation

/// Heuristic detection of generic assistant refusals (Llama “no objective” boilerplate), shared by objective workers and mission retry.
enum MetaRefusalText {
    static func isLikelyRefusal(_ text: String) -> Bool {
        let t = text.lowercased()
        let needles = [
            "don't have any specific",
            "don't have any predefined",
            "no predefined goals",
            "no missions to execute",
            "don't have any mission",
            "i don't have any instructions",
            "i can provide information and assist",
            "i am ready to assist",
            "however, i don't have",
            "don't have any specific objective",
        ]
        return needles.contains { t.contains($0) }
    }

    /// True when the model output tool-call structures as plain text instead of using the tool API.
    /// Llama 4 / llama3.2 sometimes emits {"tool_calls": [...]} or {"type":"function",...} as literal response text.
    static func looksLikeRawToolCallOutput(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return true
        }
        
        // Ollama-style: {"tool_calls": [...]}
        if text.contains("\"tool_calls\"") && (text.contains("\"name\"") || text.contains("\"function\"")) {
            return true
        }
        // OpenAI-style function call as text: {"type": "function", "name": "...", "parameters": {...}}
        let hasTypeFunction = text.contains("\"type\": \"function\"") || text.contains("\"type\":\"function\"")
        if hasTypeFunction && text.contains("\"name\"") {
            return true
        }
        return false
    }

    static func isInvalidResearchOutput(_ text: String) -> Bool {
        isLikelyRefusal(text) || looksLikeRawToolCallOutput(text)
    }
}
