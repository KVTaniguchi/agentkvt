import Foundation
@testable import AgentKVTMac

private actor MockOllamaState {
    let responses: [OllamaClient.Message]
    var callIndex: Int = 0

    init(responses: [OllamaClient.Message]) {
        self.responses = responses
    }

    func getNext() -> OllamaClient.Message {
        guard callIndex < responses.count else {
            return .init(role: "assistant", content: "No more mock responses.", toolCalls: nil)
        }
        let response = responses[callIndex]
        callIndex += 1
        return response
    }
}

/// Mock LLM client that returns predefined responses in order (for business-outcome integration tests).
public final class MockOllamaClient: OllamaClientProtocol {
    private let state: MockOllamaState

    public init(responses: [OllamaClient.Message]) {
        state = MockOllamaState(responses: responses)
    }

    public func chat(messages: [OllamaClient.Message], tools: [OllamaClient.ToolDef]?) async throws -> OllamaClient.Message {
        await state.getNext()
    }
}

extension OllamaClient.Message {
    /// One assistant message with tool_calls (e.g. write_action_item).
    public static func assistantWithToolCalls(_ toolCalls: [OllamaClient.ToolCall]) -> OllamaClient.Message {
        .init(role: "assistant", content: nil, toolCalls: toolCalls)
    }

    /// Final assistant message with no tool calls (ends the loop).
    public static func assistantFinal(content: String) -> OllamaClient.Message {
        .init(role: "assistant", content: content, toolCalls: nil)
    }
}

extension OllamaClient.ToolCall {
    public static func writeActionItem(title: String, systemIntent: String, payloadJson: String = "{}") -> OllamaClient.ToolCall {
        let dict: [String: String] = ["title": title, "systemIntent": systemIntent, "payloadJson": payloadJson]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let args = String(data: data, encoding: .utf8)!
        return .init(
            id: nil,
            type: "function",
            function: .init(name: "write_action_item", arguments: args)
        )
    }

    public static func sendNotificationEmail(subject: String, body: String) -> OllamaClient.ToolCall {
        let dict: [String: String] = ["subject": subject, "body": body]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let args = String(data: data, encoding: .utf8)!
        return .init(id: nil, type: "function", function: .init(name: "send_notification_email", arguments: args))
    }
}
