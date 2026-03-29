import Foundation
import Testing
@testable import ManagerCore

@Suite("ChatOllamaTranscript")
struct ChatOllamaTranscriptTests {

    @Test("Orders messages by timestamp and prepends system prompt")
    func ordersAndPrependsSystem() {
        let threadId = UUID()
        let early = ChatMessage(
            threadId: threadId,
            role: "user",
            content: "First",
            status: ChatMessageStatus.completed.rawValue,
            timestamp: Date(timeIntervalSince1970: 100)
        )
        let late = ChatMessage(
            threadId: threadId,
            role: "assistant",
            content: "Reply",
            status: ChatMessageStatus.completed.rawValue,
            timestamp: Date(timeIntervalSince1970: 200)
        )
        let msgs = ChatOllamaTranscript.messagesForAPI(systemPrompt: "SYS", threadMessages: [late, early])
        #expect(msgs.count == 3)
        #expect(msgs[0].role == "system")
        #expect(msgs[0].content == "SYS")
        #expect(msgs[1].role == "user")
        #expect(msgs[1].content == "First")
        #expect(msgs[2].role == "assistant")
        #expect(msgs[2].content == "Reply")
    }

    @Test("Skips failed user or assistant bubbles")
    func skipsFailed() {
        let threadId = UUID()
        let ok = ChatMessage(
            threadId: threadId,
            role: "user",
            content: "OK",
            status: ChatMessageStatus.completed.rawValue
        )
        let failed = ChatMessage(
            threadId: threadId,
            role: "user",
            content: "bad",
            status: ChatMessageStatus.failed.rawValue
        )
        let msgs = ChatOllamaTranscript.messagesForAPI(systemPrompt: "S", threadMessages: [ok, failed])
        #expect(msgs.count == 2)
        #expect(msgs[1].content == "OK")
    }

    @Test("Skips tool-role rows (only user and assistant are sent)")
    func skipsToolRole() {
        let threadId = UUID()
        let user = ChatMessage(threadId: threadId, role: "user", content: "Hi", status: ChatMessageStatus.completed.rawValue)
        let tool = ChatMessage(threadId: threadId, role: "tool", content: "{}", status: ChatMessageStatus.completed.rawValue)
        let msgs = ChatOllamaTranscript.messagesForAPI(systemPrompt: "SYS", threadMessages: [user, tool])
        #expect(msgs.count == 2)
        #expect(msgs[1].content == "Hi")
    }
}
