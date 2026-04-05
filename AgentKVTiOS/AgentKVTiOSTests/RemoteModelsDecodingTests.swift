import Foundation
import Testing
@testable import AgentKVTiOS

// MARK: - Helpers

private let iso8601 = ISO8601DateFormatter()

private func makeDecoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    d.dateDecodingStrategy = .iso8601
    return d
}

private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
    try makeDecoder().decode(type, from: Data(json.utf8))
}

// MARK: - IOSBackendObjective

@Suite("IOSBackendObjective decoding")
struct IOSBackendObjectiveDecodingTests {

    @Test("Decodes all required fields")
    func decodesRequiredFields() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "workspace_id": "22222222-2222-2222-2222-222222222222",
          "goal": "Plan San Diego trip",
          "status": "active",
          "priority": 3,
          "created_at": "2026-03-28T10:00:00Z",
          "updated_at": "2026-03-28T11:00:00Z"
        }
        """
        let obj = try decode(IOSBackendObjective.self, from: json)

        #expect(obj.id == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(obj.goal == "Plan San Diego trip")
        #expect(obj.status == "active")
        #expect(obj.priority == 3)
    }

    @Test("Decodes pending status")
    func decodesPendingStatus() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "workspace_id": "22222222-2222-2222-2222-222222222222",
          "goal": "Low priority idea",
          "status": "pending",
          "priority": 0,
          "created_at": "2026-03-28T10:00:00Z",
          "updated_at": "2026-03-28T10:00:00Z"
        }
        """
        let obj = try decode(IOSBackendObjective.self, from: json)
        #expect(obj.status == "pending")
        #expect(obj.priority == 0)
    }

    @Test("Decodes single-objective envelope from create or PATCH response")
    func decodesObjectiveEnvelope() throws {
        let json = """
        {
          "objective": {
            "id": "11111111-1111-1111-1111-111111111111",
            "workspace_id": "22222222-2222-2222-2222-222222222222",
            "goal": "Updated prompt",
            "status": "active",
            "priority": 2,
            "created_at": "2026-03-28T10:00:00Z",
            "updated_at": "2026-03-28T12:00:00Z"
          }
        }
        """
        let decoder = makeDecoder()
        let envelope = try decoder.decode(IOSBackendObjectiveEnvelope.self, from: Data(json.utf8))
        #expect(envelope.objective.goal == "Updated prompt")
        #expect(envelope.objective.priority == 2)
    }
}

// MARK: - IOSBackendObjective envelope (test-only type visibility)

private struct IOSBackendObjectiveEnvelope: Decodable {
    let objective: IOSBackendObjective
}

// MARK: - IOSBackendTask

@Suite("IOSBackendTask decoding")
struct IOSBackendTaskDecodingTests {

    @Test("Decodes task with optional result_summary nil")
    func decodesNoSummary() throws {
        let json = """
        {
          "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
          "objective_id": "11111111-1111-1111-1111-111111111111",
          "description": "Search for flights",
          "status": "pending",
          "result_summary": null,
          "created_at": "2026-03-28T10:00:00Z",
          "updated_at": "2026-03-28T10:00:00Z"
        }
        """
        let task = try decode(IOSBackendTask.self, from: json)
        #expect(task.description == "Search for flights")
        #expect(task.status == "pending")
        #expect(task.resultSummary == nil)
    }

    @Test("Decodes completed task with result_summary")
    func decodesCompletedWithSummary() throws {
        let json = """
        {
          "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
          "objective_id": "11111111-1111-1111-1111-111111111111",
          "description": "Compare hotel prices",
          "status": "completed",
          "result_summary": "Best deal: Grand Hyatt at $189/night",
          "created_at": "2026-03-28T10:00:00Z",
          "updated_at": "2026-03-28T12:00:00Z"
        }
        """
        let task = try decode(IOSBackendTask.self, from: json)
        #expect(task.status == "completed")
        #expect(task.resultSummary == "Best deal: Grand Hyatt at $189/night")
    }
}

// MARK: - IOSBackendResearchSnapshot

@Suite("IOSBackendResearchSnapshot decoding")
struct IOSBackendResearchSnapshotDecodingTests {

    @Test("Decodes snapshot with no delta")
    func decodesNoDelta() throws {
        let json = """
        {
          "id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
          "objective_id": "11111111-1111-1111-1111-111111111111",
          "task_id": null,
          "key": "mortgage_rate",
          "value": "6.85%",
          "previous_value": null,
          "delta_note": null,
          "checked_at": "2026-03-28T09:00:00Z",
          "created_at": "2026-03-28T09:00:00Z",
          "updated_at": "2026-03-28T09:00:00Z"
        }
        """
        let snap = try decode(IOSBackendResearchSnapshot.self, from: json)
        #expect(snap.key == "mortgage_rate")
        #expect(snap.value == "6.85%")
        #expect(snap.previousValue == nil)
        #expect(snap.deltaNote == nil)
        #expect(snap.taskId == nil)
    }

    @Test("Decodes snapshot with delta info")
    func decodesDelta() throws {
        let json = """
        {
          "id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
          "objective_id": "11111111-1111-1111-1111-111111111111",
          "task_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
          "key": "mortgage_rate",
          "value": "7.10%",
          "previous_value": "6.85%",
          "delta_note": "Changed from 6.85% to 7.10%",
          "checked_at": "2026-03-28T10:00:00Z",
          "created_at": "2026-03-28T09:00:00Z",
          "updated_at": "2026-03-28T10:00:00Z"
        }
        """
        let snap = try decode(IOSBackendResearchSnapshot.self, from: json)
        #expect(snap.previousValue == "6.85%")
        #expect(snap.deltaNote == "Changed from 6.85% to 7.10%")
        #expect(snap.taskId == UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
    }
}

// MARK: - IOSBackendObjectiveDetail

@Suite("IOSBackendObjectiveDetail decoding")
struct IOSBackendObjectiveDetailDecodingTests {

    @Test("Decodes nested tasks and research_snapshots arrays")
    func decodesNestedCollections() throws {
        let json = """
        {
          "objective": {
            "id": "11111111-1111-1111-1111-111111111111",
            "workspace_id": "22222222-2222-2222-2222-222222222222",
            "goal": "Track mortgage rates",
            "status": "active",
            "priority": 1,
            "created_at": "2026-03-28T10:00:00Z",
            "updated_at": "2026-03-28T10:00:00Z"
          },
          "tasks": [
            {
              "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
              "objective_id": "11111111-1111-1111-1111-111111111111",
              "description": "Fetch current 30-yr rate",
              "status": "completed",
              "result_summary": "6.85%",
              "created_at": "2026-03-28T10:00:00Z",
              "updated_at": "2026-03-28T11:00:00Z"
            }
          ],
          "research_snapshots": [
            {
              "id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
              "objective_id": "11111111-1111-1111-1111-111111111111",
              "task_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
              "key": "30yr_rate",
              "value": "6.85%",
              "previous_value": null,
              "delta_note": null,
              "checked_at": "2026-03-28T11:00:00Z",
              "created_at": "2026-03-28T11:00:00Z",
              "updated_at": "2026-03-28T11:00:00Z"
            }
          ],
          "agent_logs": [
            {
              "id": "cccccccc-cccc-cccc-cccc-cccccccccccc",
              "workspace_id": "22222222-2222-2222-2222-222222222222",
              "phase": "worker_claim",
              "content": "Claimed a board work unit",
              "metadata_json": {
                "objective_id": "11111111-1111-1111-1111-111111111111",
                "worker_label": "objective-worker-1"
              },
              "tool_name": null,
              "timestamp": "2026-03-28T11:05:00Z",
              "created_at": "2026-03-28T11:05:00Z",
              "updated_at": "2026-03-28T11:05:00Z"
            }
          ],
          "online_agent_registrations_count": 2
        }
        """
        let detail = try decode(IOSBackendObjectiveDetail.self, from: json)
        #expect(detail.objective.goal == "Track mortgage rates")
        #expect(detail.tasks.count == 1)
        #expect(detail.tasks[0].description == "Fetch current 30-yr rate")
        #expect(detail.researchSnapshots.count == 1)
        #expect(detail.researchSnapshots[0].key == "30yr_rate")
        #expect(detail.agentLogs.count == 1)
        #expect(detail.agentLogs[0].phase == "worker_claim")
        #expect(detail.onlineAgentRegistrationsCount == 2)
    }

    @Test("Decodes empty tasks and snapshots arrays")
    func decodesEmptyCollections() throws {
        let json = """
        {
          "objective": {
            "id": "11111111-1111-1111-1111-111111111111",
            "workspace_id": "22222222-2222-2222-2222-222222222222",
            "goal": "New objective",
            "status": "pending",
            "priority": 0,
            "created_at": "2026-03-28T10:00:00Z",
            "updated_at": "2026-03-28T10:00:00Z"
          },
          "tasks": [],
          "research_snapshots": []
        }
        """
        let detail = try decode(IOSBackendObjectiveDetail.self, from: json)
        #expect(detail.tasks.isEmpty)
        #expect(detail.researchSnapshots.isEmpty)
        #expect(detail.onlineAgentRegistrationsCount == 0)
    }
}
