import Foundation
import SwiftData
import Testing
@testable import AgentKVTMac
@testable import ManagerCore

private actor PlanningClientState {
    var callCount = 0

    func nextCall() -> Int {
        callCount += 1
        return callCount
    }
}

private final class InvalidPlanningThenSlowClient: OllamaClientProtocol, @unchecked Sendable {
    private let state = PlanningClientState()

    func chat(
        messages: [OllamaClient.Message],
        tools: [OllamaClient.ToolDef]?
    ) async throws -> OllamaClient.Message {
        let currentCall = await state.nextCall()

        if currentCall == 1 {
            return .assistantFinal(content: "not json")
        }

        try await Task.sleep(for: .seconds(5))
        return .assistantFinal(content: "Slow follow-up response")
    }
}

private func makePlanningContainer() throws -> (ModelContainer, ModelContext) {
    let schema = Schema([
        LifeContext.self,
        ActionItem.self,
        AgentLog.self,
        InboundFile.self,
        ChatThread.self,
        ChatMessage.self,
        IncomingEmailSummary.self,
        WorkUnit.self,
        EphemeralPin.self,
        ResourceHealth.self,
        FamilyMember.self,
        ResearchSnapshot.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    return (container, ModelContext(container))
}

private func makePlanningPool<C: OllamaClientProtocol & Sendable>(
    container: ModelContainer,
    context: ModelContext,
    client: C,
    timeoutSeconds: TimeInterval = 20
) -> ObjectiveExecutionPool {
    let registry = ToolRegistry()
    let taskRunner = AgentTaskRunner(modelContext: context, client: client, registry: registry)
    return ObjectiveExecutionPool(
        modelContainer: container,
        client: client,
        taskRunner: taskRunner,
        backendClient: nil,
        maxConcurrentWorkers: 1,
        researchSettleTimeoutSeconds: timeoutSeconds
    )
}

private func planningTaskSearchJSON(
    taskId: UUID,
    objectiveId: UUID,
    description: String,
    objectiveGoal: String? = nil
) -> String {
    var payload: [String: Any] = [
        "agentkvt": "run_task_search",
        "task_id": taskId.uuidString,
        "objective_id": objectiveId.uuidString,
        "description": description
    ]
    if let objectiveGoal {
        payload["objective_goal"] = objectiveGoal
    }
    let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

@Test("Recommendation-style objective tasks skip extra research decomposition")
func recommendationTasksSkipExtraResearchDecomposition() async throws {
    let (container, context) = try makePlanningContainer()
    let client = MockOllamaClient(responses: [
        .assistantFinal(content: "Recommend the best option and book it today.")
    ])
    let pool = makePlanningPool(container: container, context: context, client: client)

    let taskId = UUID()
    let objectiveId = UUID()
    let description = "Turn the current research into a concrete recommendation with next steps"
    let payload = try #require(TaskSearchPayload(json: planningTaskSearchJSON(
        taskId: taskId,
        objectiveId: objectiveId,
        description: description,
        objectiveGoal: "Use the current findings to recommend the best next move."
    )))

    await pool.enqueue(payload)

    let deadline = Date().addingTimeInterval(4)
    var createdUnits: [WorkUnit] = []
    while Date() < deadline {
        let readContext = ModelContext(container)
        let units = try readContext.fetch(FetchDescriptor<WorkUnit>())
            .filter { $0.objectiveId == objectiveId && $0.sourceTaskId == taskId }
        if units.contains(where: { $0.workType == "objective_synthesis" }) {
            createdUnits = units
            break
        }
        try await Task.sleep(for: .milliseconds(100))
    }

    #expect(createdUnits.contains(where: { $0.workType == "objective_synthesis" }))
    #expect(!createdUnits.contains(where: { $0.workType == "objective_research" }))
}

@Test("Concrete research directives do not fan out into generic fallback sub-tasks")
func concreteResearchDirectivesAvoidGenericFallbackSubtasks() async throws {
    let (container, context) = try makePlanningContainer()
    let pool = makePlanningPool(
        container: container,
        context: context,
        client: InvalidPlanningThenSlowClient(),
        timeoutSeconds: 20
    )

    let taskId = UUID()
    let objectiveId = UUID()
    let description = "Compare official park hours and early-entry windows for July 11"
    let payload = try #require(TaskSearchPayload(json: planningTaskSearchJSON(
        taskId: taskId,
        objectiveId: objectiveId,
        description: description,
        objectiveGoal: "Plan a realistic first day at Universal Orlando for a group of 8."
    )))

    await pool.enqueue(payload)

    let deadline = Date().addingTimeInterval(4)
    var researchUnits: [WorkUnit] = []
    while Date() < deadline {
        let readContext = ModelContext(container)
        let units = try readContext.fetch(FetchDescriptor<WorkUnit>())
            .filter {
                $0.objectiveId == objectiveId &&
                $0.sourceTaskId == taskId &&
                $0.workType == "objective_research"
            }
        if !units.isEmpty {
            researchUnits = units
            break
        }
        try await Task.sleep(for: .milliseconds(100))
    }

    #expect(researchUnits.count == 1)
    #expect(researchUnits.first?.title == description)
    #expect(!researchUnits.contains(where: { $0.title.contains("Research logistics and costs for:") }))
    #expect(!researchUnits.contains(where: { $0.title.contains("Identify risks, deadlines, and constraints for:") }))
}
