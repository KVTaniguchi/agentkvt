import Foundation
import SwiftData
import Testing
@testable import ManagerCore

struct ManagerCoreModelTests {

    @Test("ResearchSnapshot can be created and has expected properties")
    func researchSnapshotCreation() throws {
        let snap = ResearchSnapshot(
            key: "hotel_rate",
            lastKnownValue: "$199",
            deltaNote: "down $10"
        )
        #expect(snap.key == "hotel_rate")
        #expect(snap.lastKnownValue == "$199")
        #expect(snap.deltaNote == "down $10")
    }

    @Test("ActionItem can be created and has expected properties")
    func actionItemCreation() throws {
        let item = ActionItem(
            title: "Review: Acme Corp - Senior iOS",
            systemIntent: SystemIntent.urlOpen.rawValue,
            payloadData: "{\"url\":\"https://example.com/job\"}".data(using: .utf8)
        )
        #expect(item.title == "Review: Acme Corp - Senior iOS")
        #expect(item.systemIntent == SystemIntent.urlOpen.rawValue)
        #expect(item.isHandled == false)
        #expect(item.relevanceScore == 1.0)
    }

    @Test("LifeContext can be created with key and value")
    func lifeContextCreation() throws {
        let ctx = LifeContext(key: "goals", value: "Senior iOS in Philly")
        #expect(ctx.key == "goals")
        #expect(ctx.value == "Senior iOS in Philly")
    }

    @Test("InboundFile can be created with default values")
    func inboundFileCreation() throws {
        let data = "hello".data(using: .utf8)!
        let file = InboundFile(fileName: "test.txt", fileData: data)
        #expect(file.fileName == "test.txt")
        #expect(file.fileData == data)
        #expect(file.isProcessed == false)
    }

    @Test("ChatThread and ChatMessage can be created with expected defaults")
    func chatModelCreation() throws {
        let thread = ChatThread(title: "Quick Chat", allowedToolIds: ["write_action_item"])
        let pendingMessage = ChatMessage(
            threadId: thread.id,
            role: "user",
            content: "Help me plan tomorrow",
            status: ChatMessageStatus.pending.rawValue
        )

        #expect(thread.title == "Quick Chat")
        #expect(thread.allowedToolIds == ["write_action_item"])
        #expect(!thread.systemPrompt.isEmpty)
        #expect(pendingMessage.threadId == thread.id)
        #expect(pendingMessage.role == "user")
        #expect(pendingMessage.status == ChatMessageStatus.pending.rawValue)
    }

    @Test("WorkUnit, EphemeralPin, and ResourceHealth persist in SwiftData")
    func stigmergyModelsRoundTrip() throws {
        let schema = Schema([
            LifeContext.self,
            ActionItem.self,
            AgentLog.self,
            InboundFile.self,
            ChatThread.self,
            ChatMessage.self,
            WorkUnit.self,
            EphemeralPin.self,
            ResourceHealth.self,
            FamilyMember.self,
            ResearchSnapshot.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let wu = WorkUnit(
            title: "Trip",
            category: "travel",
            state: WorkUnitState.pending.rawValue,
            moundPayload: #"{"flight_info":null}"#.data(using: .utf8),
            activePhaseHint: "flights"
        )
        context.insert(wu)
        let pin = EphemeralPin(content: "Check weather", strength: 2.0, expiresAt: Date().addingTimeInterval(60))
        context.insert(pin)
        let health = ResourceHealth(resourceKey: "api.example.com", cooldownUntil: Date().addingTimeInterval(300))
        context.insert(health)
        let member = FamilyMember(displayName: "Test User", symbol: "🙂")
        context.insert(member)
        try context.save()

        let wuFetched = try context.fetch(FetchDescriptor<WorkUnit>()).first
        #expect(wuFetched?.title == "Trip")
        #expect(wuFetched?.category == "travel")
        let pins = try context.fetch(FetchDescriptor<EphemeralPin>())
        #expect(pins.count == 1)
        #expect(pins[0].content == "Check weather")
        let rh = try context.fetch(FetchDescriptor<ResourceHealth>()).first
        #expect(rh?.resourceKey == "api.example.com")
        let members = try context.fetch(FetchDescriptor<FamilyMember>())
        #expect(members.count == 1)
        #expect(members[0].displayName == "Test User")
    }

    @Test("SwiftData schema accepts all model types in one container")
    func schemaAndContainer() throws {
        let schema = Schema([
            LifeContext.self,
            ActionItem.self,
            AgentLog.self,
            InboundFile.self,
            ChatThread.self,
            ChatMessage.self,
            WorkUnit.self,
            EphemeralPin.self,
            ResourceHealth.self,
            FamilyMember.self,
            ResearchSnapshot.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let snap = ResearchSnapshot(key: "metric", lastKnownValue: "42")
        context.insert(snap)

        let item = ActionItem(title: "Test action", systemIntent: "test")
        context.insert(item)

        let thread = ChatThread(title: "Assistant")
        context.insert(thread)

        let message = ChatMessage(threadId: thread.id, role: "assistant", content: "Hello there")
        context.insert(message)

        try context.save()

        let snapDesc = FetchDescriptor<ResearchSnapshot>()
        let snaps = try context.fetch(snapDesc)
        #expect(snaps.count == 1)
        #expect(snaps[0].key == "metric")

        let itemDesc = FetchDescriptor<ActionItem>()
        let items = try context.fetch(itemDesc)
        #expect(items.count == 1)

        let threadDesc = FetchDescriptor<ChatThread>()
        let threads = try context.fetch(threadDesc)
        #expect(threads.count == 1)

        let messageDesc = FetchDescriptor<ChatMessage>()
        let messages = try context.fetch(messageDesc)
        #expect(messages.count == 1)
        #expect(messages[0].threadId == thread.id)
    }

    @Test("Deleting an ActionItem persists removal across SwiftData contexts")
    func actionItemDeletionPersistsAcrossContexts() throws {
        let schema = Schema([
            ActionItem.self,
            AgentLog.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let actionItem = ActionItem(
            title: "Review nightly briefing",
            systemIntent: SystemIntent.urlOpen.rawValue
        )
        let log = AgentLog(
            phase: "assistant_final",
            content: "Mission completed successfully."
        )

        context.insert(actionItem)
        context.insert(log)
        try context.save()

        context.delete(actionItem)
        try context.save()

        let verificationContext = ModelContext(container)
        let actionItems = try verificationContext.fetch(FetchDescriptor<ActionItem>())
        let logs = try verificationContext.fetch(FetchDescriptor<AgentLog>())

        #expect(actionItems.isEmpty)
        #expect(logs.count == 1)
        #expect(logs[0].phase == "assistant_final")
    }
}
