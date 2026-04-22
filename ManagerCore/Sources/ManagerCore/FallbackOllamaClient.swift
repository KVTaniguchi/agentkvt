import Foundation

/// Wraps a primary OllamaClientProtocol and falls back to a secondary when the
/// primary fails with a network or overload error (timeout, connection refused, 503, 429).
///
/// Also enforces a wall-clock deadline on the primary. If the primary does not finish
/// within `primaryTimeoutSeconds` (default 120 s), it is cancelled and the fallback is
/// tried — catching cases where Ollama is running but generating tokens too slowly to
/// ever complete in reasonable time.
public final class FallbackOllamaClient: OllamaClientProtocol, @unchecked Sendable {
    private let primary: any OllamaClientProtocol
    private let fallback: any OllamaClientProtocol
    private let primaryTimeoutSeconds: Double

    public init(
        primary: any OllamaClientProtocol,
        fallback: any OllamaClientProtocol,
        primaryTimeoutSeconds: Double = 120
    ) {
        self.primary = primary
        self.fallback = fallback
        self.primaryTimeoutSeconds = primaryTimeoutSeconds
    }

    public func isHealthy() async -> Bool {
        if await primary.isHealthy() { return true }
        return await fallback.isHealthy()
    }

    public func chat(messages: [OllamaClient.Message], tools: [OllamaClient.ToolDef]?) async throws -> OllamaClient.Message {
        do {
            return try await withPrimaryTimeout {
                try await self.primary.chat(messages: messages, tools: tools)
            }
        } catch {
            guard Self.isOverloadError(error) else { throw error }
            print("[FallbackOllamaClient] Primary failed (\(error.localizedDescription)) — routing to fallback")
            do {
                let response = try await fallback.chat(messages: messages, tools: tools)
                print("[FallbackOllamaClient] Fallback succeeded")
                return response
            } catch {
                print("[FallbackOllamaClient] Fallback also failed: \(error.localizedDescription)")
                throw error
            }
        }
    }

    static func isOverloadError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return [.timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet]
                .contains(urlError.code)
        }
        switch error as? OllamaError {
        case .httpStatus(503), .httpStatus(429): return true
        default: return false
        }
    }

    /// Races `body` against a deadline. If the deadline fires first, the body task is
    /// cancelled and URLError(.timedOut) is thrown so the caller's fallback logic applies.
    private func withPrimaryTimeout<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(for: .seconds(self.primaryTimeoutSeconds))
                throw URLError(.timedOut)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
