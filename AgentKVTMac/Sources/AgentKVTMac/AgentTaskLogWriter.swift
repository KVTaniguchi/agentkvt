import Foundation
import ManagerCore
import SwiftData

public protocol AgentTaskLogWriting: Sendable {
    func writeLog(
        taskName: String,
        phase: String,
        content: String,
        toolName: String?
    ) async
}

private func taskMetadata(toolName: String?) -> [String: String] {
    var metadata: [String: String] = [:]
    if let toolName, !toolName.isEmpty {
        metadata["tool_name"] = toolName
    }
    if let context = AgentTaskExecutionContext.current {
        metadata["task_name"] = context.taskName
        if let objectiveId = context.objectiveId {
            metadata["objective_id"] = objectiveId.uuidString
        }
        if let taskId = context.taskId {
            metadata["task_id"] = taskId.uuidString
        }
        if let workUnitId = context.workUnitId {
            metadata["work_unit_id"] = workUnitId.uuidString
        }
        if let workerLabel = context.workerLabel, !workerLabel.isEmpty {
            metadata["worker_label"] = workerLabel
        }
    }
    return metadata
}

struct SwiftDataAgentTaskLogWriter: AgentTaskLogWriting, @unchecked Sendable {
    let modelContext: ModelContext

    func writeLog(
        taskName: String,
        phase: String,
        content: String,
        toolName: String?
    ) async {
        let log = AgentLog(
            phase: phase,
            content: content,
            toolName: toolName
        )
        modelContext.insert(log)

        do {
            try modelContext.save()
        } catch {
            print("[AgentTaskRunner] Failed to save SwiftData log '\\(phase)' for '\\(taskName)': \\(error)")
        }
    }
}

struct BackendAgentTaskLogWriter: AgentTaskLogWriting {
    let backendClient: BackendAPIClient

    func writeLog(
        taskName: String,
        phase: String,
        content: String,
        toolName: String?
    ) async {
        do {
            _ = try await backendClient.createAgentLog(
                taskName: taskName,
                phase: phase,
                content: content,
                metadata: taskMetadata(toolName: toolName)
            )
        } catch {
            print("[AgentTaskRunner] Failed to send workspace log '\\(phase)' for '\\(taskName)': \\(error)")
        }
    }
}
