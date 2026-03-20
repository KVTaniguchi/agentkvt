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
            allowedMCPTools: ["write_action_item", "web_search_and_fetch"]
        )
        #expect(mission.missionName == "Find a job")
        #expect(mission.triggerSchedule == "weekly|sunday")
        #expect(mission.allowedMCPTools.count == 2)
        #expect(mission.isEnabled == true)
        #expect(mission.lastRunAt == nil)
    }

    @Test("ActionItem can be created and has expected properties")
    func actionItemCreation() throws {
        let item = ActionItem(
            title: "Review: Acme Corp - Senior iOS",
            systemIntent: "open_url",
            payloadData: "{\"url\":\"https://example.com/job\"}".data(using: .utf8)
        )
        #expect(item.title == "Review: Acme Corp - Senior iOS")
        #expect(item.systemIntent == "open_url")
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

    @Test("SwiftData schema accepts all model types in one container")
    func schemaAndContainer() throws {
        let schema = Schema([
            LifeContext.self,
            MissionDefinition.self,
            ActionItem.self,
            AgentLog.self,
            InboundFile.self
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

        try context.save()

        let missionDesc = FetchDescriptor<MissionDefinition>()
        let missions = try context.fetch(missionDesc)
        #expect(missions.count == 1)
        #expect(missions[0].missionName == "Test")

        let itemDesc = FetchDescriptor<ActionItem>()
        let items = try context.fetch(itemDesc)
        #expect(items.count == 1)
        #expect(items[0].missionId == mission.id)
    }
}
