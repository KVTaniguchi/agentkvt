import Foundation
import ManagerCore
import SwiftData

public protocol MissionLogWriting: Sendable {
    func writeLog(
        missionId: UUID,
        missionName: String,
        phase: String,
        content: String,
        toolName: String?
    ) async
}

private func missionMetadata(toolName: String?) -> [String: String] {
    var metadata: [String: String] = [:]
    if let toolName, !toolName.isEmpty {
        metadata["tool_name"] = toolName
    }
    if let context = MissionExecutionContext.current {
        metadata["mission_name"] = context.missionName
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

struct SwiftDataMissionLogWriter: MissionLogWriting, @unchecked Sendable {
    let modelContext: ModelContext

    func writeLog(
        missionId: UUID,
        missionName: String,
        phase: String,
        content: String,
        toolName: String?
    ) async {
        let log = AgentLog(
            missionId: missionId,
            missionName: missionName,
            phase: phase,
            content: content,
            toolName: toolName
        )
        modelContext.insert(log)

        do {
            try modelContext.save()
        } catch {
            print("[MissionRunner] Failed to save SwiftData log '\(phase)' for '\(missionName)': \(error)")
        }
    }
}

struct BackendMissionLogWriter: MissionLogWriting {
    let backendClient: BackendAPIClient

    func writeLog(
        missionId: UUID,
        missionName: String,
        phase: String,
        content: String,
        toolName: String?
    ) async {
        do {
            _ = try await backendClient.createLog(
                missionId: missionId,
                phase: phase,
                content: content,
                metadata: missionMetadata(toolName: toolName)
            )
        } catch {
            print("[MissionRunner] Failed to send backend log '\(phase)' for '\(missionName)': \(error)")
        }
    }
}

struct BackendWorkspaceLogWriter: MissionLogWriting {
    let backendClient: BackendAPIClient

    func writeLog(
        missionId: UUID,
        missionName: String,
        phase: String,
        content: String,
        toolName: String?
    ) async {
        do {
            _ = try await backendClient.createAgentLog(
                missionName: missionName,
                phase: phase,
                content: content,
                metadata: missionMetadata(toolName: toolName)
            )
        } catch {
            print("[MissionRunner] Failed to send workspace log '\(phase)' for '\(missionName)': \(error)")
        }
    }
}
