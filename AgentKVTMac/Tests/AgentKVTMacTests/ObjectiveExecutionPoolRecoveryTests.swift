import Foundation
import SwiftData
import Testing
@testable import AgentKVTMac
@testable import ManagerCore

private actor HangingOllamaClient: OllamaClientProtocol {
    func chat(
        messages: [OllamaClient.Message],
        tools: [OllamaClient.ToolDef]?
    ) async throws -> OllamaClient.Message {
        try await Task.sleep(for: .seconds(5))
        return .init(role: "assistant", content: "Delayed response", toolCalls: nil)
    }
}

private struct ObjectiveExecutionPoolRecoveryTests {
    private func makeContainer() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            LifeContext.self,
            MissionDefinition.self,
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

    private func makePool(
        container: ModelContainer,
        context: ModelContext,
        client: any OllamaClientProtocol,
        timeoutSeconds: TimeInterval
    ) -> ObjectiveExecutionPool {
        let registry = ToolRegistry()
        let runner = MissionRunner(modelContext: context, client: client, registry: registry)
        return ObjectiveExecutionPool(
            modelContainer: container,
            client: client,
            missionRunner: runner,
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

    @Test("Supervisor timeout creates visible stalled ActionItem")
    func supervisorTimeoutCreatesStallActionItem() async throws {
        let (container, context) = try makeContainer()
        let pool = makePool(
            container: container,
            context: context,
            client: HangingOllamaClient(),
            timeoutSeconds: 0.2
        )

        let payload = TaskSearchPayload(
            taskId: UUID().uuidString,
            objectiveId: UUID().uuidString,
            description: "Plan Tokyo trip",
            objectiveGoal: nil
        )
        await pool.enqueue(payload)

        let deadline = Date().addingTimeInterval(3)
        var found = false
        while Date() < deadline {
            let readContext = ModelContext(container)
            let items = try readContext.fetch(FetchDescriptor<ActionItem>())
            if items.contains(where: { $0.title.contains("Agent Stalled:") && $0.title.contains("timed out.") }) {
                found = true
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(found, "Expected timeout path to create an 'Agent Stalled' ActionItem.")
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
}
