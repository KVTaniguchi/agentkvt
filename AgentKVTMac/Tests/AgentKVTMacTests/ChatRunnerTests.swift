import Foundation
import SwiftData
import Testing
@testable import AgentKVTMac
@testable import ManagerCore

private func makeChatTestContainer() throws -> (ModelContext, ModelContainer) {
    let schema = Schema([
        LifeContext.self,
        WorkUnit.self,
        AgentLog.self,
        InboundFile.self,
        ChatThread.self,
        ChatMessage.self,
        FamilyMember.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)
    return (context, container)
}

struct ChatRunnerTests {

    @Test("Pending user chat message is completed and assistant reply is persisted")
    func processesPendingChatMessage() async throws {
        let (context, _) = try makeChatTestContainer()
        let registry = ToolRegistry()

        let thread = ChatThread(title: "General Assistant")
        context.insert(thread)
        context.insert(ChatMessage(
            threadId: thread.id,
            role: "user",
            content: "Help me organize tomorrow",
            status: ChatMessageStatus.pending.rawValue
        ))
        try context.save()

        let mockClient = MockOllamaClient(responses: [
            .assistantFinal(content: "Start with your highest-energy task in the morning.")
        ])

        let runner = ChatRunner(modelContext: context, client: mockClient, registry: registry)
        let didProcess = try await runner.processNextPendingMessage()
        #expect(didProcess == true)

        let messageDesc = FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        let messages = try context.fetch(messageDesc)
        #expect(messages.count == 2)
        #expect(messages[0].status == ChatMessageStatus.completed.rawValue)
        #expect(messages[1].role == "assistant")
        #expect(messages[1].content.contains("highest-energy"))

        let logDesc = FetchDescriptor<AgentLog>()
        let logs = try context.fetch(logDesc)
        #expect(logs.contains { $0.phase == "assistant_final" || $0.phase == "chat_outcome" })
    }

    @Test("Older chat threads with no explicit tools fall back to default chat tools")
    func emptyToolThreadsCanUseDefaultStatusTool() async throws {
        let (context, _) = try makeChatTestContainer()
        let registry = ToolRegistry()
        registry.register(makeFetchWorkUnitsTool(modelContext: context))

        context.insert(WorkUnit(title: "Plan family trip", category: "travel", state: WorkUnitState.pending.rawValue))

        let thread = ChatThread(title: "Work Status", allowedToolIds: [])
        context.insert(thread)
        context.insert(ChatMessage(
            threadId: thread.id,
            role: "user",
            content: "What work is pending?",
            status: ChatMessageStatus.pending.rawValue
        ))
        try context.save()

        let mockClient = MockOllamaClient(responses: [
            .assistantWithToolCalls([
                .init(
                    id: nil,
                    type: "function",
                    function: .init(
                        name: "fetch_work_units",
                        arguments: #"{"state":"pending"}"#
                    )
                )
            ]),
            .assistantFinal(content: "There is one pending work unit: Plan family trip.")
        ])

        let runner = ChatRunner(modelContext: context, client: mockClient, registry: registry)
        let didProcess = try await runner.processNextPendingMessage()
        #expect(didProcess == true)

        let messages = try context.fetch(FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.timestamp, order: .forward)]))
        #expect(messages.count == 2)
        #expect(messages[1].content.contains("Plan family trip"))

        let logs = try context.fetch(FetchDescriptor<AgentLog>())
        #expect(logs.contains { $0.phase == "tool_result" })
    }
}
