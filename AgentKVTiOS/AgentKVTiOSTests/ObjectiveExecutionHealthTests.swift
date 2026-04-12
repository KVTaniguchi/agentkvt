import Foundation
import Testing
@testable import AgentKVTiOS

private func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
    try makeDecoder().decode(type, from: Data(json.utf8))
}

private func makeObjective(
    id: String = "11111111-1111-1111-1111-111111111111",
    status: String = "active"
) throws -> IOSBackendObjective {
    try decode(IOSBackendObjective.self, from: """
    {
      "id": "\(id)",
      "workspace_id": "22222222-2222-2222-2222-222222222222",
      "goal": "Monitor retirement planning",
      "status": "\(status)",
      "priority": 0,
      "created_at": "2026-04-12T16:00:00Z",
      "updated_at": "2026-04-12T16:00:00Z"
    }
    """)
}

private func makeTask(
    id: String,
    objectiveID: String = "11111111-1111-1111-1111-111111111111",
    status: String,
    createdAt: String,
    updatedAt: String
) throws -> IOSBackendTask {
    try decode(IOSBackendTask.self, from: """
    {
      "id": "\(id)",
      "objective_id": "\(objectiveID)",
      "source_feedback_id": null,
      "description": "Research task",
      "status": "\(status)",
      "result_summary": null,
      "created_at": "\(createdAt)",
      "updated_at": "\(updatedAt)"
    }
    """)
}

private func makeLog(
    id: String,
    taskID: String,
    phase: String,
    timestamp: String
) throws -> IOSBackendAgentLog {
    try decode(IOSBackendAgentLog.self, from: """
    {
      "id": "\(id)",
      "workspace_id": "22222222-2222-2222-2222-222222222222",
      "phase": "\(phase)",
      "content": "Task update",
      "metadata_json": {
        "task_id": "\(taskID)"
      },
      "tool_name": null,
      "timestamp": "\(timestamp)",
      "created_at": "\(timestamp)",
      "updated_at": "\(timestamp)"
    }
    """)
}

@Suite("ObjectiveExecutionHealth")
struct ObjectiveExecutionHealthTests {
    @Test("Marks active work as stalled when the newest task update is too old")
    func marksActiveWorkAsStalled() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-04-12T20:00:00Z"))
        let objective = try makeObjective()
        let activeTaskID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        let tasks = [
            try makeTask(
                id: activeTaskID,
                status: "in_progress",
                createdAt: "2026-04-12T16:00:00Z",
                updatedAt: "2026-04-12T16:08:00Z"
            ),
            try makeTask(
                id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
                status: "pending",
                createdAt: "2026-04-12T16:10:00Z",
                updatedAt: "2026-04-12T16:10:00Z"
            )
        ]
        let logs = [
            try makeLog(
                id: "99999999-9999-9999-9999-999999999991",
                taskID: activeTaskID,
                phase: "worker_claim",
                timestamp: "2026-04-12T16:05:00Z"
            )
        ]

        let health = ObjectiveExecutionHealth.assess(
            objective: objective,
            tasks: tasks,
            agentLogs: logs,
            referenceDate: now
        )

        #expect(health.hasInProgressWork)
        #expect(health.hasStalledActiveWork)
        #expect((health.freshestActiveSilence ?? 0) >= health.staleThreshold)
    }

    @Test("Fresh task logs keep running work out of the stalled state")
    func freshTaskLogsKeepWorkHealthy() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-04-12T20:00:00Z"))
        let objective = try makeObjective()
        let activeTaskID = "cccccccc-cccc-cccc-cccc-cccccccccccc"
        let tasks = [
            try makeTask(
                id: activeTaskID,
                status: "in_progress",
                createdAt: "2026-04-12T16:00:00Z",
                updatedAt: "2026-04-12T16:03:00Z"
            )
        ]
        let logs = [
            try makeLog(
                id: "99999999-9999-9999-9999-999999999992",
                taskID: activeTaskID,
                phase: "worker_claim",
                timestamp: "2026-04-12T16:00:00Z"
            ),
            try makeLog(
                id: "99999999-9999-9999-9999-999999999993",
                taskID: activeTaskID,
                phase: "tool_result",
                timestamp: "2026-04-12T19:58:00Z"
            )
        ]

        let health = ObjectiveExecutionHealth.assess(
            objective: objective,
            tasks: tasks,
            agentLogs: logs,
            referenceDate: now
        )

        #expect(health.hasInProgressWork)
        #expect(!health.hasStalledActiveWork)
        #expect((health.freshestActiveSilence ?? .infinity) < health.staleThreshold)
    }
}
