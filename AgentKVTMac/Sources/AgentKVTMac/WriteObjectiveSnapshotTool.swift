import Foundation

/// MCP tool that persists a research result for a Supervisor-layer Objective
/// directly to the Rails Postgres backend (via BackendAPIClient).
///
/// Use this after calling `multi_step_search` inside a webhook-triggered mission
/// that was launched by the Rails `TaskExecutorJob`. The server upserts the snapshot,
/// tracks the delta, and records it as a research snapshot.
public func makeWriteObjectiveSnapshotTool(backendClient: BackendAPIClient) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "write_objective_snapshot",
        name: "write_objective_snapshot",
        description: """
            Persist a research result for a Supervisor Objective to the Rails database.
            Call this after multi_step_search completes for a webhook-dispatched task.
            The server detects value changes and records delta notes automatically.
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
                    description: "UUID of the Task that triggered this search (from the webhook payload)."
                ),
                "key": .init(
                    type: "string",
                    description: "Stable logical name for the tracked metric, e.g. 'loews_coronado_nightly_rate'"
                ),
                "value": .init(
                    type: "string",
                    description: "Plain-language research finding. Or if snapshot_kind=exudate, structural metadata like CSS selectors."
                ),
                "sentiment": .init(
                    type: "string",
                    description: "Optional. 'negative' if this branch is a permanent dead end (e.g. sold out). Defaults to 'neutral'."
                ),
                "repellent_reason": .init(
                    type: "string",
                    description: "Optional. Reason for dead end, if sentiment=negative."
                ),
                "repellent_scope": .init(
                    type: "string",
                    description: "Optional. Domain or entity that is a dead end, e.g. 'loews.com' or 'checkout', if sentiment=negative."
                ),
                "snapshot_kind": .init(
                    type: "string",
                    description: "Optional. 'result' for answers, 'exudate' for environmental metadata. Defaults to 'result'."
                ),
                "mark_task_completed": .init(
                    type: "boolean",
                    description: "Optional. Set true only on the final synthesis snapshot that should mark the parent task complete. Defaults to false."
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
            let markTaskCompleted = (args["mark_task_completed"] as? Bool) ?? false
            let sentiment = (args["sentiment"] as? String)?.lowercased() ?? "neutral"
            let isRepellent = sentiment == "negative"
            let repellentReason = args["repellent_reason"] as? String
            let repellentScope = args["repellent_scope"] as? String
            let snapshotKind = (args["snapshot_kind"] as? String)?.lowercased() ?? "result"

            if snapshotKind != "exudate", let msg = ObjectiveResearchSnapshotPayload.clientRejectionMessageIfInvalid(value) {
                return "Error: \(msg)"
            }

            do {
                let snapshot = try await backendClient.writeResearchSnapshot(
                    objectiveId: objectiveId,
                    taskId: taskId,
                    key: key,
                    value: value,
                    isRepellent: isRepellent,
                    repellentReason: repellentReason,
                    repellentScope: repellentScope,
                    snapshotKind: snapshotKind,
                    markTaskCompleted: markTaskCompleted
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
