import Foundation

/// Loads existing objective research snapshots from Postgres so workers can avoid duplicate work.
public func makeReadObjectiveSnapshotTool(backendClient: BackendAPIClient) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "read_objective_snapshot",
        name: "read_objective_snapshot",
        description: """
            Load research snapshots for this objective from the server database. \
            Call at the start of a work unit (and again if needed) to see findings other workers already recorded. \
            Optionally pass task_id to include objective-wide snapshots plus this task's rows only.
            """,
        parameters: .init(
            type: "object",
            properties: [
                "objective_id": .init(type: "string", description: "UUID of the Objective"),
                "task_id": .init(
                    type: "string",
                    description: "Optional task UUID; narrows to snapshots with no task or this task."
                )
            ],
            required: ["objective_id"]
        ),
        handler: { args in
            guard let objectiveIdString = args["objective_id"] as? String,
                  let objectiveId = UUID(uuidString: objectiveIdString) else {
                return "Error: objective_id (UUID) is required."
            }
            let taskId = (args["task_id"] as? String).flatMap { UUID(uuidString: $0) }

            do {
                let snapshots = try await backendClient.fetchResearchSnapshots(
                    objectiveId: objectiveId,
                    taskId: taskId
                )
                if snapshots.isEmpty {
                    return "No research snapshots on the server yet for this scope. You may be the first worker—use multi_step_search, then write_objective_snapshot with plain-language findings."
                }
                let lines = snapshots.prefix(50).map { s in
                    let taskNote = s.taskId.map { " task=\($0.uuidString)" } ?? " task=(objective-wide)"
                    return "- key=\(s.key)\(taskNote) value=\(s.value)"
                }
                let body = lines.joined(separator: "\n")
                if body.count > 14_000 {
                    return "Existing findings on the server:\n" + String(body.prefix(14_000)) + "\n… (truncated)"
                }
                return "Existing findings on the server:\n\(body)"
            } catch {
                return "Error reading objective snapshots: \(error.localizedDescription)"
            }
        }
    )
}
