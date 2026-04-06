import Foundation
import SwiftData
import Testing
@testable import AgentKVTMac
@testable import ManagerCore

/// Slow client to exercise supervisor timeout paths.
private final class HangingOllamaClient: OllamaClientProtocol, @unchecked Sendable {
    func chat(
        messages: [OllamaClient.Message],
        tools: [OllamaClient.ToolDef]?
    ) async throws -> OllamaClient.Message {
        try await Task.sleep(for: .seconds(5))
        return .init(role: "assistant", content: "Delayed response", toolCalls: nil)
    }
}

private func makeContainer() throws -> (ModelContainer, ModelContext) {
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

private func makePool<C: OllamaClientProtocol & Sendable>(
    container: ModelContainer,
    context: ModelContext,
    client: C,
    timeoutSeconds: TimeInterval
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

private func payloadData(
    objectiveId: UUID,
    taskId: UUID,
    taskDescription: String
) throws -> Data {
    let json: [String: Any?] = [
        "objectiveId": objectiveId.uuidString,
        "taskId": taskId.uuidString,
        "rootTaskDescription": taskDescription,
        "parentObjectiveGoal": nil,
        "workDescription": "Research subtask",
        "planningRound": 1,
        "workType": "objective_research",
        "resultSummary": nil,
        "lastError": nil,
    ]
    return try JSONSerialization.data(withJSONObject: json.compactMapValues { $0 }, options: [])
}

private func taskSearchJSON(taskId: UUID, objectiveId: UUID, description: String) -> String {
    """
    {"agentkvt":"run_task_search","task_id":"\(taskId.uuidString)","objective_id":"\(objectiveId.uuidString)","description":"\(description)"}
    """
}

@Test("Supervisor timeout creates visible stalled ActionItem")
func supervisorTimeoutCreatesStallActionItem() async throws {
    let (container, context) = try makeContainer()
    let pool = makePool(
        container: container,
        context: context,
        client: HangingOllamaClient(),
        timeoutSeconds: 0.2
    )

    let tid = UUID()
    let oid = UUID()
    let json = taskSearchJSON(taskId: tid, objectiveId: oid, description: "Plan Tokyo trip")
    let payload = try #require(TaskSearchPayload(json: json))
    await pool.enqueue(payload)

    // `waitForResearchToSettle` sleeps up to 2s before the first timeout check, then calls
    // `handleResearchTimeout` which creates the ActionItem; allow enough wall time for the supervisor.
    let deadline = Date().addingTimeInterval(12)
    var found = false
    while Date() < deadline {
        let readContext = ModelContext(container)
        let items = try readContext.fetch(FetchDescriptor<ActionItem>())
        if items.contains(where: { $0.title.contains("Agent Stalled") }) {
            found = true
            break
        }
        try await Task.sleep(for: .milliseconds(150))
    }
    #expect(found, "Expected research settle timeout to create an 'Agent Stalled' ActionItem.")
}

@Test("Startup sweep resumes orphaned objective by creating synthesis unit")
func startupSweepCreatesMissingSynthesisUnit() async throws {
    let (container, context) = try makeContainer()
    let objectiveId = UUID()
    let taskId = UUID()
    let taskDescription = "Build a family travel plan"

    let root = WorkUnit(
        title: taskDescription,
        category: "objective",
        objectiveId: objectiveId,
        sourceTaskId: taskId,
        workType: "objective_root",
        state: WorkUnitState.inProgress.rawValue
    )
    let research = WorkUnit(
        title: "Research flight options",
        category: "objective",
        objectiveId: objectiveId,
        sourceTaskId: taskId,
        workType: "objective_research",
        state: WorkUnitState.done.rawValue,
        moundPayload: try payloadData(objectiveId: objectiveId, taskId: taskId, taskDescription: taskDescription),
        activePhaseHint: "research"
    )
    context.insert(root)
    context.insert(research)
    try context.save()

    let pool = makePool(
        container: container,
        context: context,
        client: MockOllamaClient(responses: [.assistantFinal(content: "ok")]),
        timeoutSeconds: 5
    )
    await pool.start()

    let deadline = Date().addingTimeInterval(3)
    var synthesisExists = false
    while Date() < deadline {
        let readContext = ModelContext(container)
        let units = try readContext.fetch(FetchDescriptor<WorkUnit>())
        if units.contains(where: {
            $0.objectiveId == objectiveId &&
            $0.sourceTaskId == taskId &&
            $0.workType == "objective_synthesis"
        }) {
            synthesisExists = true
            break
        }
        try await Task.sleep(for: .milliseconds(100))
    }

    #expect(synthesisExists, "Expected startup sweep to create missing synthesis work unit for orphaned objective.")
}
