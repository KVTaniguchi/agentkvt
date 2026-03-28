import Foundation

/// MCP tool that persists a research result for a Supervisor-layer Objective
/// directly to the Rails Postgres backend (via BackendAPIClient).
///
/// Use this after calling `multi_step_search` inside a webhook-triggered mission
/// that was launched by the Rails `TaskExecutorJob`. The server upserts the snapshot,
/// tracks the delta, and schedules an ActionItem for any meaningful change.
public func makeWriteObjectiveSnapshotTool(backendClient: BackendAPIClient) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "write_objective_snapshot",
        name: "write_objective_snapshot",
        description: """
            Persist a research result for a Supervisor Objective to the Rails database.
            Call this after multi_step_search completes for a webhook-dispatched task.
            The server detects value changes and raises an ActionItem automatically.
            """,
        parameters: .init(
            type: "object",
            properties: [
                "objective_id": .init(
                    type: "string",
                    description: "UUID of the Objective this snapshot belongs to (from the webhook payload)"
                ),
                "task_id": .init(
                    type: "string",
                    description: "UUID of the Task that triggered this search (from the webhook payload). Providing this marks the task completed."
                ),
                "key": .init(
                    type: "string",
                    description: "Stable logical name for the tracked metric, e.g. 'loews_coronado_nightly_rate'"
                ),
                "value": .init(
                    type: "string",
                    description: "The newly observed value (price, text, count, etc.)"
                )
            ],
            required: ["objective_id", "key", "value"]
        ),
        handler: { args in
            guard let objectiveIdString = args["objective_id"] as? String,
                  let objectiveId = UUID(uuidString: objectiveIdString),
                  let key = args["key"] as? String, !key.isEmpty,
                  let value = args["value"] as? String else {
                return "Error: objective_id (UUID), key, and value are required."
            }

            let taskId: UUID? = (args["task_id"] as? String).flatMap { UUID(uuidString: $0) }

            do {
                let snapshot = try await backendClient.writeResearchSnapshot(
                    objectiveId: objectiveId,
                    taskId: taskId,
                    key: key,
                    value: value
                )
                if let delta = snapshot.deltaNote {
                    return "changed: \(delta)"
                }
                return "unchanged: key=\(snapshot.key) value=\(snapshot.value)"
            } catch {
                return "Error writing objective snapshot: \(error.localizedDescription)"
            }
        }
    )
}
