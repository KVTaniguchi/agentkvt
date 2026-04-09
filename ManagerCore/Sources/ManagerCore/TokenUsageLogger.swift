import Foundation

/// Appends one JSONL entry per Ollama call to ~/Library/Logs/AgentKVT/token_usage.jsonl.
/// Only active on macOS (the Mac agent is the only LLM caller). No-ops on iOS.
/// Fire-and-forget; errors are silently ignored so logging never breaks the agent.
public actor TokenUsageLogger {
    public static let shared = TokenUsageLogger()
    private init() {}

    public func record(model: String, promptTokens: Int, completionTokens: Int) {
#if os(macOS)
        let entry: [String: Any] = [
            "ts": ISO8601DateFormatter().string(from: Date()),
            "provider": "ollama",
            "model": model,
            "input_tokens": promptTokens,
            "output_tokens": completionTokens
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              let line = String(data: data, encoding: .utf8) else { return }
        guard let logURL = Self.logURL else { return }
        appendLine(line + "\n", to: logURL)
#endif
    }

#if os(macOS)
    private static let logURL: URL? = {
        let logsDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AgentKVT", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        return logsDir.appendingPathComponent("token_usage.jsonl")
    }()

    private func appendLine(_ text: String, to url: URL) {
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
#endif
}
