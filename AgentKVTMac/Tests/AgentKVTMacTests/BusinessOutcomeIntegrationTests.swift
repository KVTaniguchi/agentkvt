import Foundation
import SwiftData
import Testing
@testable import AgentKVTMac
@testable import ManagerCore

// MARK: - Test harness: in-memory store + registry

private func makeTestContainer() throws -> (ModelContext, ModelContainer) {
    let schema = Schema([
        LifeContext.self,
        MissionDefinition.self,
        ActionItem.self,
        AgentLog.self
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)
    return (context, container)
}

private func makeTestRegistry(
    modelContext: ModelContext,
    includeSendNotification: Bool = false,
    includeBeeAI: Bool = false,
    notificationOutboxDir: URL? = nil
) -> ToolRegistry {
    let registry = ToolRegistry()
    registry.register(makeWriteActionItemTool(modelContext: modelContext))
    if includeSendNotification, let outbox = notificationOutboxDir {
        registry.register(makeSendNotificationEmailTool(
            destinationEmail: "test@test.com",
            sendVia: .outbox(directory: outbox)
        ))
    }
    if includeBeeAI {
        registry.register(makeFetchBeeAIContextTool(modelContext: modelContext))
    }
    return registry
}

// MARK: - 1. Job Scout Pipeline Test

struct JobScoutPipelineTest {

    @Test("When a job mission is due, agent creates exactly one Review ActionItem and outcome log")
    func jobScoutCreatesReviewActionAndOutcomeLog() async throws {
        let (context, _) = try makeTestContainer()
        let registry = makeTestRegistry(modelContext: context)

        let mission = MissionDefinition(
            missionName: "Tech Job Scout",
            systemPrompt: "You are a job scout. Identify high-match iOS roles and create one action per lead.",
            triggerSchedule: "weekly|sunday",
            allowedMCPTools: ["write_action_item"]
        )
        mission.isEnabled = true
        context.insert(mission)
        try context.save()

        let mockClient = MockOllamaClient(responses: [
            .assistantWithToolCalls([
                .writeActionItem(title: "Review: Acme Corp - Senior iOS Lead", systemIntent: "open_url", payloadJson: "{\"url\":\"https://jobs.example.com/1\"}")
            ]),
            .assistantFinal(content: "Found one high-match iOS role (Acme Corp). One low-match Android role was skipped.")
        ])

        let runner = MissionRunner(modelContext: context, client: mockClient, registry: registry)
        try await runner.run(mission)

        let itemDesc = FetchDescriptor<ActionItem>()
        let items = try context.fetch(itemDesc)
        #expect(items.count == 1, "Expected exactly one ActionItem after run (handshake: Mac creates button for iPhone); got \(items.count)")
        let reviewItem = items.first!
        #expect(reviewItem.title.contains("Review"), "Expected ActionItem title to contain 'Review', got '\(reviewItem.title)'")
        #expect(reviewItem.relevanceScore >= 0.8, "Expected relevanceScore >= 0.8 (default is 1.0)")

        let logDesc = FetchDescriptor<AgentLog>(predicate: #Predicate<AgentLog> { $0.phase == "outcome" })
        let logs = try context.fetch(logDesc)
        #expect(logs.count >= 1, "Expected at least one AgentLog with phase 'outcome'")
        #expect(logs.contains { $0.content.contains("high-match") || $0.content.contains("Acme") })
    }
}

// MARK: - 2. Impulsive Expense Guard Test

struct ImpulsiveExpenseGuardTest {

    @Test("Budget Sentinel flags $45 impulsive charge but not $200 utility; systemIntent is review_purchase")
    func budgetSentinelFlagsImpulsiveOnly() async throws {
        let (context, _) = try makeTestContainer()
        let registry = makeTestRegistry(modelContext: context)

        let mission = MissionDefinition(
            missionName: "Budget Sentinel",
            systemPrompt: "Flag impulsive expenses between $20 and $50. Do not flag utility bills or expenses over $100. Create one action per flagged transaction with systemIntent review_purchase.",
            triggerSchedule: "daily|09:00",
            allowedMCPTools: ["write_action_item"]
        )
        mission.isEnabled = true
        context.insert(mission)
        try context.save()

        let dropzoneContext = """
        Transactions:
        - $45 Coffee & Pastry (cafe)
        - $200 Utility Bill (electric)
        """

        let mockClient = MockOllamaClient(responses: [
            .assistantWithToolCalls([
                .writeActionItem(title: "Review: $45 Coffee & Pastry", systemIntent: "review_purchase")
            ]),
            .assistantFinal(content: "Flagged one impulsive charge ($45). $200 utility bill not in range.")
        ])

        let runner = MissionRunner(modelContext: context, client: mockClient, registry: registry)
        try await runner.run(mission, additionalContext: dropzoneContext)

        let itemDesc = FetchDescriptor<ActionItem>()
        let items = try context.fetch(itemDesc)
        let purchaseReview = items.filter { $0.systemIntent == "review_purchase" }
        #expect(purchaseReview.count == 1, "Expected exactly one ActionItem with systemIntent review_purchase")
        #expect(purchaseReview[0].title.contains("45") || purchaseReview[0].title.contains("Coffee"))

        let forUtility = items.filter { $0.title.contains("200") || $0.title.contains("Utility") }
        #expect(forUtility.isEmpty, "Expected no ActionItem for the $200 utility bill")
    }
}

// MARK: - 3. Homeschool Lesson Delivery Test

struct HomeschoolLessonDeliveryTest {

    @Test("Lesson mission creates outbox file and ActionItem 'Launch Today's Lesson'")
    func homeschoolLessonCreatesOutboxAndAction() async throws {
        let outboxDir = FileManager.default.temporaryDirectory.appending(path: "agentkvt-test-outbox-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outboxDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outboxDir) }

        let (context, _) = try makeTestContainer()
        let registry = makeTestRegistry(modelContext: context, includeSendNotification: true, notificationOutboxDir: outboxDir)

        let mission = MissionDefinition(
            missionName: "Homeschool Lesson",
            systemPrompt: "Create a Harry Potter themed chemistry lesson. Send a notification email with the lesson summary and create an action 'Launch Today's Lesson'.",
            triggerSchedule: "daily|08:00",
            allowedMCPTools: ["write_action_item", "send_notification_email"]
        )
        mission.isEnabled = true
        context.insert(mission)
        try context.save()

        let mockClient = MockOllamaClient(responses: [
            .assistantWithToolCalls([
                .sendNotificationEmail(subject: "Today's Lesson: Harry Potter Chemistry", body: "See attached lesson plan."),
                .writeActionItem(title: "Launch Today's Lesson", systemIntent: "open_lesson")
            ]),
            .assistantFinal(content: "Lesson created and notification sent.")
        ])

        let runner = MissionRunner(modelContext: context, client: mockClient, registry: registry)
        try await runner.run(mission)

        let itemDesc = FetchDescriptor<ActionItem>()
        let items = try context.fetch(itemDesc)
        let launchItem = items.filter { $0.title.contains("Launch") && $0.title.contains("Lesson") }
        #expect(launchItem.count == 1, "Expected one ActionItem titled 'Launch Today's Lesson'")

        let outboxContents = (try? FileManager.default.contentsOfDirectory(at: outboxDir, includingPropertiesForKeys: nil)) ?? []
        #expect(!outboxContents.isEmpty, "Expected at least one file in Agent outbox")

        let logDesc = FetchDescriptor<AgentLog>()
        let logs = try context.fetch(logDesc)
        let emailLogged = logs.contains { $0.toolName == "send_notification_email" } || logs.contains { $0.content.contains("notification") || $0.content.contains("outbox") }
        #expect(emailLogged, "Expected AgentLog to record send_notification_email or outbox")
    }
}

// MARK: - 4. Sovereign Context (BEE AI) Update Test
// Business outcome: agent "learns" from voice notes (BEE AI) and updates internal facts;
// subsequent missions (e.g. Job Scout) can then prioritize using this context.

struct SovereignContextUpdateTest {

    @Test("Context Sync mission updates LifeContext from mock BEE transcript; focus_areas includes Swift 6")
    func contextSyncUpdatesLifeContextFromBeeTranscript() async throws {
        let (context, _) = try makeTestContainer()
        let registry = makeTestRegistry(modelContext: context, includeBeeAI: true)

        let mission = MissionDefinition(
            missionName: "Context Sync",
            systemPrompt: "Fetch BEE AI context and store the summary under the key focus_areas so future missions can prioritize accordingly.",
            triggerSchedule: "daily|07:00",
            allowedMCPTools: ["fetch_bee_ai_context"]
        )
        mission.isEnabled = true
        context.insert(mission)
        try context.save()

        let mockBeeJson = """
        {"insights":[{"text":"I want to focus more on Swift 6 Concurrency this month","timestamp":"2025-03-15T10:00:00Z"}]}
        """
        setenv("MOCK_BEE_AI_RESPONSE_JSON", mockBeeJson, 1)

        let mockClient = MockOllamaClient(responses: [
            .assistantWithToolCalls([
                OllamaClient.ToolCall(
                    id: nil,
                    type: "function",
                    function: .init(name: "fetch_bee_ai_context", arguments: "{\"store_as_life_context_key\":\"focus_areas\"}")
                )
            ]),
            .assistantFinal(content: "Stored BEE AI context under focus_areas.")
        ])

        let runner = MissionRunner(modelContext: context, client: mockClient, registry: registry)
        try await runner.run(mission)

        unsetenv("MOCK_BEE_AI_RESPONSE_JSON")

        let ctxDesc = FetchDescriptor<LifeContext>(predicate: #Predicate<LifeContext> { $0.key == "focus_areas" })
        let contexts = try context.fetch(ctxDesc)
        #expect(contexts.count == 1, "Expected one LifeContext with key focus_areas")
        #expect(contexts[0].value.contains("Swift 6") || contexts[0].value.contains("Concurrency"))

        let oneMinuteAgo = Date().addingTimeInterval(-60)
        #expect(contexts[0].updatedAt >= oneMinuteAgo, "Expected focus_areas updatedAt to be current")
    }
}
