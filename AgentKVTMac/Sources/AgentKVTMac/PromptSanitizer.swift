import Foundation

extension String {
    /// Escapes angle-bracket characters so user-supplied text cannot break out of
    /// XML-style delimiters used in LLM system prompts (e.g. <user_goal>...</user_goal>).
    /// This does NOT guarantee injection-safety against all models but raises the bar
    /// significantly for all current Ollama/Claude targets.
    func sanitizedForPrompt() -> String {
        self
            .replacingOccurrences(of: "<", with: "‹")
            .replacingOccurrences(of: ">", with: "›")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
