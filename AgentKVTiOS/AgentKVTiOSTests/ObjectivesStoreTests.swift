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

private final class MockObjectivesSync: ObjectivesRemoteSyncing, @unchecked Sendable {
    var isEnabled = true
    var objectives: [IOSBackendObjective] = []
    var updateLog: [(UUID, String, String, Int)] = []
    var runNowIds: [UUID] = []
    var deletedIds: [UUID] = []

    func fetchObjectivesRemote() async throws -> [IOSBackendObjective] {
        objectives
    }

    func createObjectiveRemote(goal: String, status: String, priority: Int) async throws -> IOSBackendObjective {
        fatalError("unused in these tests")
    }

    func fetchObjectiveDetailRemote(id: UUID) async throws -> IOSBackendObjectiveDetail {
        fatalError("unused in these tests")
    }

    func updateObjectiveRemote(id: UUID, goal: String, status: String, priority: Int) async throws -> IOSBackendObjective {
        updateLog.append((id, goal, status, priority))
        return try makeObjective(id: id, goal: goal, status: status, priority: priority)
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
}
