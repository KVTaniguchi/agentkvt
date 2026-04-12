import Foundation

/// Appends one JSONL entry per Ollama call to ~/Library/Logs/AgentKVT/token_usage.jsonl.
/// Only active on macOS (the Mac agent is the only LLM caller). No-ops on iOS.
/// Fire-and-forget; errors are silently ignored so logging never breaks the agent.
///
/// To tag a call with task context, set the TaskLocal before running the agent loop:
///   await TokenUsageLogger.$currentTask.withValue("objective-planner") { ... }
public actor TokenUsageLogger {
    public static let shared = TokenUsageLogger()
    private init() {}

    /// Set this TaskLocal to label which agent task triggered the LLM call.
    @TaskLocal public static var currentTask: String = "unknown"

    // Cloud rates used for savings calculation (Claude Sonnet pricing as baseline).
    private static let inputRatePerMToken = 3.00   // USD per 1M input tokens
    private static let outputRatePerMToken = 15.00  // USD per 1M output tokens

    public func record(model: String, promptTokens: Int, completionTokens: Int, latencyMs: Int) {
#if os(macOS)
        let savings = savings(input: promptTokens, output: completionTokens)
        let entry: [String: Any] = [
            "ts": ISO8601DateFormatter().string(from: Date()),
            "model": model,
            "task": TokenUsageLogger.currentTask,
            "tokens": ["in": promptTokens, "out": completionTokens],
            "latency_ms": latencyMs,
            "savings_usd": savings
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: .sortedKeys),
              let line = String(data: data, encoding: .utf8) else { return }
        guard let logURL = Self.logURL else { return }
        appendLine(line + "\n", to: logURL)
#endif
    }

    private func savings(input: Int, output: Int) -> Double {
        let inputCost = Double(input) / 1_000_000 * Self.inputRatePerMToken
        let outputCost = Double(output) / 1_000_000 * Self.outputRatePerMToken
        return (inputCost + outputCost).rounded(to: 6)
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

private extension Double {
    func rounded(to places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
