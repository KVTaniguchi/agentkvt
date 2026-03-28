import Foundation
import Testing
import AgentKVTMac

struct WebhookChatSignalTests {

    @Test("matches canonical JSON body")
    func matchesCanonical() {
        #expect(WebhookChatSignal.matches(#"{"agentkvt":"process_chat"}"#))
    }

    @Test("matches when body has surrounding whitespace")
    func matchesTrimmed() {
        #expect(WebhookChatSignal.matches("  \n{\"agentkvt\":\"process_chat\"}\t  "))
    }

    @Test("rejects other agentkvt values")
    func rejectsOtherSignals() {
        #expect(!WebhookChatSignal.matches(#"{"agentkvt":"webhook"}"#))
        #expect(!WebhookChatSignal.matches("{}"))
        #expect(!WebhookChatSignal.matches(""))
    }
}
