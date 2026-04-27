import Foundation
import Testing
@testable import AgentKVTiOS

// MARK: - Mock

private func makeObjective(
    id: UUID,
    goal: String,
    status: String = "active",
    priority: Int = 0
) throws -> IOSBackendObjective {
    let json = """
    {
      "id": "\(id.uuidString)",
      "workspace_id": "22222222-2222-2222-2222-222222222222",
      "goal": "\(goal.replacingOccurrences(of: "\"", with: "\\\""))",
      "status": "\(status)",
      "priority": \(priority),
      "created_at": "2026-03-28T10:00:00Z",
      "updated_at": "2026-03-28T11:00:00Z"
    }
    """
    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(IOSBackendObjective.self, from: data)
}

private func makeObjectiveFeedback(
    id: UUID,
    objectiveId: UUID,
    content: String,
    feedbackKind: String = "follow_up",
    status: String = "queued",
    taskId: UUID? = nil,
    researchSnapshotId: UUID? = nil
) throws -> IOSBackendObjectiveFeedback {
    let taskValue = taskId.map { "\"\($0.uuidString)\"" } ?? "null"
    let snapshotValue = researchSnapshotId.map { "\"\($0.uuidString)\"" } ?? "null"
    let json = """
    {
      "id": "\(id.uuidString)",
      "objective_id": "\(objectiveId.uuidString)",
      "task_id": \(taskValue),
      "research_snapshot_id": \(snapshotValue),
      "role": "user",
      "feedback_kind": "\(feedbackKind)",
      "status": "\(status)",
      "content": "\(content.replacingOccurrences(of: "\"", with: "\\\""))",
      "created_at": "2026-04-10T10:00:00Z",
      "updated_at": "2026-04-10T10:01:00Z"
    }
    """
    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(IOSBackendObjectiveFeedback.self, from: data)
}

private func makeResearchSnapshotFeedback(
    id: UUID = UUID(uuidString: "abababab-abab-abab-abab-abababababab")!,
    objectiveId: UUID,
    snapshotId: UUID,
    createdByProfileId: UUID?,
    rating: String,
    reason: String?
) throws -> IOSBackendResearchSnapshotFeedback {
    let profileValue = createdByProfileId.map { "\"\($0.uuidString)\"" } ?? "null"
    let reasonValue = reason.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" } ?? "null"
    let json = """
    {
      "id": "\(id.uuidString)",
      "workspace_id": "22222222-2222-2222-2222-222222222222",
      "objective_id": "\(objectiveId.uuidString)",
      "research_snapshot_id": "\(snapshotId.uuidString)",
      "created_by_profile_id": \(profileValue),
      "role": "user",
      "rating": "\(rating)",
      "reason": \(reasonValue),
      "created_at": "2026-04-10T10:00:00Z",
      "updated_at": "2026-04-10T10:01:00Z"
    }
    """
    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(IOSBackendResearchSnapshotFeedback.self, from: data)
}

private final class MockObjectivesSync: ObjectivesRemoteSyncing, @unchecked Sendable {
    var isEnabled = true
    var objectives: [IOSBackendObjective] = []
    var updateLog: [(UUID, String, String, Int)] = []
    var feedbackSubmissions: [(UUID, String, String, UUID?, UUID?)] = []
    var feedbackUpdates: [(UUID, UUID, String, String, UUID?, UUID?)] = []
    var approveFeedbackPlanCalls: [(UUID, UUID)] = []
    var regenerateFeedbackPlanCalls: [(UUID, UUID)] = []
    var snapshotFeedbackSubmissions: [(UUID, UUID, UUID?, String, String?)] = []
    var snapshotFeedbackUpdates: [(UUID, UUID, UUID, UUID?, String, String?)] = []
    var approvePlanIds: [UUID] = []
    var regeneratePlanIds: [UUID] = []
    var runNowIds: [UUID] = []
    var deletedIds: [UUID] = []

    func fetchObjectivesRemote() async throws -> [IOSBackendObjective] {
        objectives
    }

    func createObjectiveRemote(goal: String, status: String, priority: Int, inboundFileIds: [UUID]) async throws -> IOSBackendObjective {
        fatalError("unused in these tests")
    }

    func fetchObjectiveDetailRemote(id: UUID, viewerProfileId: UUID?) async throws -> IOSBackendObjectiveDetail {
        fatalError("unused in these tests")
    }

    func updateObjectiveRemote(id: UUID, goal: String, status: String, priority: Int) async throws -> IOSBackendObjective {
        updateLog.append((id, goal, status, priority))
        return try makeObjective(id: id, goal: goal, status: status, priority: priority)
    }

    func submitObjectiveFeedbackRemote(
        id: UUID,
        content: String,
        feedbackKind: String,
        taskId: UUID?,
        researchSnapshotId: UUID?,
        inboundFileIds: [UUID]
    ) async throws -> IOSBackendSubmitObjectiveFeedbackResult {
        feedbackSubmissions.append((id, content, feedbackKind, taskId, researchSnapshotId))
        return IOSBackendSubmitObjectiveFeedbackResult(
            objective: try makeObjective(id: id, goal: "Objective after feedback", status: "active", priority: 0),
            objectiveFeedback: try makeObjectiveFeedback(
                id: UUID(uuidString: "f1f1f1f1-f1f1-f1f1-f1f1-f1f1f1f1f1f1")!,
                objectiveId: id,
                content: content,
                feedbackKind: feedbackKind,
                taskId: taskId,
                researchSnapshotId: researchSnapshotId
            ),
            followUpTasks: []
        )
    }

    func updateObjectiveFeedbackRemote(
        objectiveId: UUID,
        feedbackId: UUID,
        content: String,
        feedbackKind: String,
        taskId: UUID?,
        researchSnapshotId: UUID?,
        inboundFileIds: [UUID]
    ) async throws -> IOSBackendSubmitObjectiveFeedbackResult {
        feedbackUpdates.append((objectiveId, feedbackId, content, feedbackKind, taskId, researchSnapshotId))
        return IOSBackendSubmitObjectiveFeedbackResult(
            objective: try makeObjective(id: objectiveId, goal: "Objective after feedback edit", status: "active", priority: 0),
            objectiveFeedback: try makeObjectiveFeedback(
                id: feedbackId,
                objectiveId: objectiveId,
                content: content,
                feedbackKind: feedbackKind,
                taskId: taskId,
                researchSnapshotId: researchSnapshotId
            ),
            followUpTasks: []
        )
    }

    func approveObjectiveFeedbackPlanRemote(objectiveId: UUID, feedbackId: UUID) async throws -> IOSBackendSubmitObjectiveFeedbackResult {
        approveFeedbackPlanCalls.append((objectiveId, feedbackId))
        return IOSBackendSubmitObjectiveFeedbackResult(
            objective: try makeObjective(id: objectiveId, goal: "Approved feedback plan", status: "active", priority: 0),
            objectiveFeedback: try makeObjectiveFeedback(
                id: feedbackId,
                objectiveId: objectiveId,
                content: "Approved feedback plan",
                feedbackKind: "follow_up",
                status: "queued"
            ),
            followUpTasks: []
        )
    }

    func regenerateObjectiveFeedbackPlanRemote(objectiveId: UUID, feedbackId: UUID) async throws -> IOSBackendSubmitObjectiveFeedbackResult {
        regenerateFeedbackPlanCalls.append((objectiveId, feedbackId))
        return IOSBackendSubmitObjectiveFeedbackResult(
            objective: try makeObjective(id: objectiveId, goal: "Regenerated feedback plan", status: "active", priority: 0),
            objectiveFeedback: try makeObjectiveFeedback(
                id: feedbackId,
                objectiveId: objectiveId,
                content: "Regenerated feedback plan",
                feedbackKind: "follow_up",
                status: "review_required"
            ),
            followUpTasks: []
        )
    }

    func submitResearchSnapshotFeedbackRemote(
        objectiveId: UUID,
        snapshotId: UUID,
        createdByProfileId: UUID?,
        rating: String,
        reason: String?
    ) async throws -> IOSBackendResearchSnapshotFeedback {
        snapshotFeedbackSubmissions.append((objectiveId, snapshotId, createdByProfileId, rating, reason))
        return try makeResearchSnapshotFeedback(
            objectiveId: objectiveId,
            snapshotId: snapshotId,
            createdByProfileId: createdByProfileId,
            rating: rating,
            reason: reason
        )
    }

    func updateResearchSnapshotFeedbackRemote(
        objectiveId: UUID,
        snapshotId: UUID,
        feedbackId: UUID,
        createdByProfileId: UUID?,
        rating: String,
        reason: String?
    ) async throws -> IOSBackendResearchSnapshotFeedback {
        snapshotFeedbackUpdates.append((objectiveId, snapshotId, feedbackId, createdByProfileId, rating, reason))
        return try makeResearchSnapshotFeedback(
            id: feedbackId,
            objectiveId: objectiveId,
            snapshotId: snapshotId,
            createdByProfileId: createdByProfileId,
            rating: rating,
            reason: reason
        )
    }

    func approveObjectivePlanRemote(id: UUID) async throws -> IOSBackendObjective {
        approvePlanIds.append(id)
        return try makeObjective(id: id, goal: "Approved plan", status: "active", priority: 0)
    }

    func regenerateObjectivePlanRemote(id: UUID) async throws -> IOSBackendObjective {
        regeneratePlanIds.append(id)
        return try makeObjective(id: id, goal: "Regenerated plan", status: "active", priority: 0)
    }

    func runObjectiveNowRemote(id: UUID) async throws -> IOSBackendObjective {
        runNowIds.append(id)
        return try makeObjective(id: id, goal: "Run now", status: "active", priority: 0)
    }

    func resetStuckTasksAndRunObjectiveRemote(id: UUID) async throws -> IOSBackendObjective {
        fatalError("unused in these tests")
    }

    func rerunObjectiveRemote(id: UUID) async throws -> IOSBackendObjective {
        fatalError("unused in these tests")
    }

    func deleteObjectiveRemote(id: UUID) async throws {
        deletedIds.append(id)
    }
}

// MARK: - Tests

@Suite("ObjectivesStore")
struct ObjectivesStoreTests {

    @Test("updateObjective replaces matching row and forwards fields to sync")
    @MainActor
    func updateReplacesLocalRow() async throws {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let original = try makeObjective(id: id, goal: "Old", status: "active", priority: 2)
        let mock = MockObjectivesSync()
        mock.objectives = [original]

        let store = ObjectivesStore(sync: mock)
        await store.refresh()
        #expect(store.objectives.count == 1)

        let updated = try await store.updateObjective(id: id, goal: "New goal", status: "pending", priority: 3)

        #expect(updated.goal == "New goal")
        #expect(updated.status == "pending")
        #expect(updated.priority == 3)
        #expect(store.objectives.count == 1)
        #expect(store.objectives[0].goal == "New goal")
        #expect(mock.updateLog.count == 1)
        #expect(mock.updateLog[0].0 == id)
        #expect(mock.updateLog[0].1 == "New goal")
    }

    @Test("deleteObjective removes row after sync")
    @MainActor
    func deleteRemovesLocalRow() async throws {
        let a = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let b = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let oa = try makeObjective(id: a, goal: "A")
        let ob = try makeObjective(id: b, goal: "B")
        let mock = MockObjectivesSync()
        mock.objectives = [oa, ob]

        let store = ObjectivesStore(sync: mock)
        await store.refresh()
        #expect(store.objectives.count == 2)

        try await store.deleteObjective(id: a)

        #expect(mock.deletedIds == [a])
        #expect(store.objectives.count == 1)
        #expect(store.objectives[0].id == b)
    }

    @Test("runObjectiveNow updates the matching row and records the trigger")
    @MainActor
    func runNowUpdatesLocalRow() async throws {
        let id = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        let original = try makeObjective(id: id, goal: "Old", status: "pending", priority: 0)
        let mock = MockObjectivesSync()
        mock.objectives = [original]

        let store = ObjectivesStore(sync: mock)
        await store.refresh()

        let updated = try await store.runObjectiveNow(id: id)

        #expect(mock.runNowIds == [id])
        #expect(updated.status == "active")
        #expect(store.objectives[0].status == "active")
        #expect(store.objectives[0].goal == "Run now")
    }

    @Test("submitObjectiveFeedback records the payload and updates the matching objective")
    @MainActor
    func submitFeedbackUpdatesLocalRow() async throws {
        let id = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let taskId = UUID(uuidString: "12121212-1212-1212-1212-121212121212")!
        let snapshotId = UUID(uuidString: "34343434-3434-3434-3434-343434343434")!
        let original = try makeObjective(id: id, goal: "Old", status: "active", priority: 0)
        let mock = MockObjectivesSync()
        mock.objectives = [original]

        let store = ObjectivesStore(sync: mock)
        await store.refresh()

        let result = try await store.submitObjectiveFeedback(
            id: id,
            content: "Go deeper on resort fees.",
            feedbackKind: "compare_options",
            taskId: taskId,
            researchSnapshotId: snapshotId
        )

        #expect(mock.feedbackSubmissions.count == 1)
        #expect(mock.feedbackSubmissions[0].0 == id)
        #expect(mock.feedbackSubmissions[0].1 == "Go deeper on resort fees.")
        #expect(mock.feedbackSubmissions[0].2 == "compare_options")
        #expect(mock.feedbackSubmissions[0].3 == taskId)
        #expect(mock.feedbackSubmissions[0].4 == snapshotId)
        #expect(result.objectiveFeedback.feedbackKind == "compare_options")
        #expect(store.objectives[0].goal == "Objective after feedback")
    }

    @Test("updateObjectiveFeedback records the payload and updates the matching objective")
    @MainActor
    func updateFeedbackUpdatesLocalRow() async throws {
        let objectiveId = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let feedbackId = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let original = try makeObjective(id: objectiveId, goal: "Old", status: "active", priority: 0)
        let mock = MockObjectivesSync()
        mock.objectives = [original]

        let store = ObjectivesStore(sync: mock)
        await store.refresh()

        let result = try await store.updateObjectiveFeedback(
            objectiveId: objectiveId,
            feedbackId: feedbackId,
            content: "Challenge the earlier conclusion.",
            feedbackKind: "challenge_result",
            taskId: nil,
            researchSnapshotId: nil
        )

        #expect(mock.feedbackUpdates.count == 1)
        #expect(mock.feedbackUpdates[0].0 == objectiveId)
        #expect(mock.feedbackUpdates[0].1 == feedbackId)
        #expect(result.objectiveFeedback.feedbackKind == "challenge_result")
        #expect(store.objectives[0].goal == "Objective after feedback edit")
    }

    @Test("approveObjectiveFeedbackPlan records the trigger and updates the matching objective")
    @MainActor
    func approveFeedbackPlanUpdatesLocalRow() async throws {
        let objectiveId = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let feedbackId = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let original = try makeObjective(id: objectiveId, goal: "Old", status: "active", priority: 0)
        let mock = MockObjectivesSync()
        mock.objectives = [original]

        let store = ObjectivesStore(sync: mock)
        await store.refresh()

        let result = try await store.approveObjectiveFeedbackPlan(objectiveId: objectiveId, feedbackId: feedbackId)

        #expect(mock.approveFeedbackPlanCalls.count == 1)
        #expect(mock.approveFeedbackPlanCalls[0].0 == objectiveId)
        #expect(mock.approveFeedbackPlanCalls[0].1 == feedbackId)
        #expect(result.objectiveFeedback.status == "queued")
        #expect(store.objectives[0].goal == "Approved feedback plan")
    }

    @Test("regenerateObjectiveFeedbackPlan records the trigger and updates the matching objective")
    @MainActor
    func regenerateFeedbackPlanUpdatesLocalRow() async throws {
        let objectiveId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let feedbackId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let original = try makeObjective(id: objectiveId, goal: "Old", status: "active", priority: 0)
        let mock = MockObjectivesSync()
        mock.objectives = [original]

        let store = ObjectivesStore(sync: mock)
        await store.refresh()

        let result = try await store.regenerateObjectiveFeedbackPlan(objectiveId: objectiveId, feedbackId: feedbackId)

        #expect(mock.regenerateFeedbackPlanCalls.count == 1)
        #expect(mock.regenerateFeedbackPlanCalls[0].0 == objectiveId)
        #expect(mock.regenerateFeedbackPlanCalls[0].1 == feedbackId)
        #expect(result.objectiveFeedback.status == "review_required")
        #expect(store.objectives[0].goal == "Regenerated feedback plan")
    }

    @Test("approveObjectivePlan updates the matching row and records the trigger")
    @MainActor
    func approvePlanUpdatesLocalRow() async throws {
        let id = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
        let original = try makeObjective(id: id, goal: "Needs review", status: "active", priority: 0)
        let mock = MockObjectivesSync()
        mock.objectives = [original]

        let store = ObjectivesStore(sync: mock)
        await store.refresh()

        let updated = try await store.approveObjectivePlan(id: id)

        #expect(mock.approvePlanIds == [id])
        #expect(updated.status == "active")
        #expect(store.objectives[0].goal == "Approved plan")
    }

    @Test("regenerateObjectivePlan updates the matching row and records the trigger")
    @MainActor
    func regeneratePlanUpdatesLocalRow() async throws {
        let id = UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!
        let original = try makeObjective(id: id, goal: "Needs a redo", status: "active", priority: 0)
        let mock = MockObjectivesSync()
        mock.objectives = [original]

        let store = ObjectivesStore(sync: mock)
        await store.refresh()

        let updated = try await store.regenerateObjectivePlan(id: id)

        #expect(mock.regeneratePlanIds == [id])
        #expect(updated.status == "active")
        #expect(store.objectives[0].goal == "Regenerated plan")
    }
}
