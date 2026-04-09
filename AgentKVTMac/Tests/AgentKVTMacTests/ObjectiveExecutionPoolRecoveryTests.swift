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

/// Regression test for the April 2026 incident where `default-local.store`
/// became corrupted (NSSQLiteErrorDomain=1), causing all worker loops to crash
/// silently after webhook delivery. Fix: delete the store so SwiftData recreates
/// it clean. This test verifies the pool can accept a payload and create work
/// units without errors on a fresh in-memory container (equivalent to a clean store).
@Test("Fresh container after store deletion: pool creates work units without crashing")
func freshContainerAfterStoreDeletionCreatesWorkUnits() async throws {
    // Simulate a freshly recreated store by using a brand-new in-memory container.
    let (container, context) = try makeContainer()

    let pool = makePool(
        container: container,
        context: context,
        client: MockOllamaClient(responses: [.assistantFinal(content: "Research complete.")]),
        timeoutSeconds: 10
    )
    await pool.start()

    let taskId = UUID()
    let objectiveId = UUID()
    let json = taskSearchJSON(taskId: taskId, objectiveId: objectiveId, description: "Verify SEPTA API docs")
    let payload = try #require(TaskSearchPayload(json: json))
    await pool.enqueue(payload)

    // Supervisor should create at least a root WorkUnit without crashing.
    let deadline = Date().addingTimeInterval(5)
    var rootFound = false
    while Date() < deadline {
        let readContext = ModelContext(container)
        let units = try readContext.fetch(FetchDescriptor<WorkUnit>())
        if units.contains(where: { $0.objectiveId == objectiveId && $0.workType == "objective_root" }) {
            rootFound = true
            break
        }
        try await Task.sleep(for: .milliseconds(100))
    }

    #expect(rootFound, "Fresh pool should create root WorkUnit — store corruption fix regression.")
}

/// Verifies that BackendAPIClient contains no reference to `/v1/missions`,
/// confirming the old polling path was removed and will not flood the API with 404s.
@Test("BackendAPIClient source contains no v1/missions path")
func backendAPIClientHasNoMissionsPath() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()          // AgentKVTMacTests/
        .deletingLastPathComponent()          // Tests/
        .deletingLastPathComponent()          // AgentKVTMac/
        .appendingPathComponent("Sources/AgentKVTMac/BackendAPIClient.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    #expect(!source.contains("v1/missions"), "BackendAPIClient must not reference the removed /v1/missions endpoint.")
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
