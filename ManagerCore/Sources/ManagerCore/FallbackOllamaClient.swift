import Foundation

/// Wraps a primary OllamaClientProtocol and falls back to a secondary when the
/// primary fails with a network or overload error (timeout, connection refused, 503, 429).
public final class FallbackOllamaClient: OllamaClientProtocol, @unchecked Sendable {
    private let primary: any OllamaClientProtocol
    private let fallback: any OllamaClientProtocol

    public init(primary: any OllamaClientProtocol, fallback: any OllamaClientProtocol) {
        self.primary = primary
        self.fallback = fallback
    }

    public func chat(messages: [OllamaClient.Message], tools: [OllamaClient.ToolDef]?) async throws -> OllamaClient.Message {
        do {
            return try await primary.chat(messages: messages, tools: tools)
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
}
