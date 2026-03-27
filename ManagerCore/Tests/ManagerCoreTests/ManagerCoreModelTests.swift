import Foundation
import SwiftData
import Testing
@testable import ManagerCore

struct ManagerCoreModelTests {

    @Test("MissionDefinition can be created and has expected properties")
    func missionDefinitionCreation() throws {
        let mission = MissionDefinition(
            missionName: "Find a job",
            systemPrompt: "You are a career coach.",
            triggerSchedule: "weekly|sunday",
            allowedMCPTools: ["write_action_item", "web_search_and_fetch"],
            ownerProfileId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")
        )
        #expect(mission.missionName == "Find a job")
        #expect(mission.triggerSchedule == "weekly|sunday")
        #expect(mission.allowedMCPTools.count == 2)
        #expect(mission.isEnabled == true)
        #expect(mission.lastRunAt == nil)
        #expect(mission.ownerProfileId == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
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
            MissionDefinition.self,
            ActionItem.self,
            AgentLog.self,
            InboundFile.self,
            ChatThread.self,
            ChatMessage.self,
            WorkUnit.self,
            EphemeralPin.self,
            ResourceHealth.self,
            FamilyMember.self,
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
            MissionDefinition.self,
            ActionItem.self,
            AgentLog.self,
            InboundFile.self,
            ChatThread.self,
            ChatMessage.self,
            WorkUnit.self,
            EphemeralPin.self,
            ResourceHealth.self,
            FamilyMember.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let mission = MissionDefinition(
            missionName: "Test",
            systemPrompt: "Test prompt",
            triggerSchedule: "daily|09:00",
            allowedMCPTools: ["write_action_item"]
        )
        context.insert(mission)

        let item = ActionItem(title: "Test action", systemIntent: "test")
        item.missionId = mission.id
        context.insert(item)

        let thread = ChatThread(title: "Assistant")
        context.insert(thread)

        let message = ChatMessage(threadId: thread.id, role: "assistant", content: "Hello there")
        context.insert(message)

        try context.save()

        let missionDesc = FetchDescriptor<MissionDefinition>()
        let missions = try context.fetch(missionDesc)
        #expect(missions.count == 1)
        #expect(missions[0].missionName == "Test")

        let itemDesc = FetchDescriptor<ActionItem>()
        let items = try context.fetch(itemDesc)
        #expect(items.count == 1)
        #expect(items[0].missionId == mission.id)

        let threadDesc = FetchDescriptor<ChatThread>()
        let threads = try context.fetch(threadDesc)
        #expect(threads.count == 1)

        let messageDesc = FetchDescriptor<ChatMessage>()
        let messages = try context.fetch(messageDesc)
        #expect(messages.count == 1)
        #expect(messages[0].threadId == thread.id)
    }

    @Test("Deleting a mission persists removal while mission-linked rows remain readable")
    func missionDeletionPersistsAcrossContexts() throws {
        let schema = Schema([
            MissionDefinition.self,
            ActionItem.self,
            AgentLog.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let mission = MissionDefinition(
            missionName: "Nightly Briefing",
            systemPrompt: "Summarize the latest updates.",
            triggerSchedule: "daily|20:00",
            allowedMCPTools: ["write_action_item"]
        )
        let actionItem = ActionItem(
            title: "Review nightly briefing",
            systemIntent: SystemIntent.urlOpen.rawValue,
            missionId: mission.id
        )
        let log = AgentLog(
            missionId: mission.id,
            missionName: mission.missionName,
            phase: "outcome",
            content: "Mission completed successfully."
        )

        context.insert(mission)
        context.insert(actionItem)
        context.insert(log)
        try context.save()

        context.delete(mission)
        try context.save()

        let verificationContext = ModelContext(container)
        let missions = try verificationContext.fetch(FetchDescriptor<MissionDefinition>())
        let actionItems = try verificationContext.fetch(FetchDescriptor<ActionItem>())
        let logs = try verificationContext.fetch(FetchDescriptor<AgentLog>())

        #expect(missions.isEmpty)
        #expect(actionItems.count == 1)
        #expect(actionItems[0].missionId == mission.id)
        #expect(logs.count == 1)
        #expect(logs[0].missionId == mission.id)
        #expect(logs[0].missionName == "Nightly Briefing")
    }
}
