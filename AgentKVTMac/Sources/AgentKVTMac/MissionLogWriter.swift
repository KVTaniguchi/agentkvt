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
                toolName: toolName
            )
        } catch {
            print("[MissionRunner] Failed to send backend log '\(phase)' for '\(missionName)': \(error)")
        }
    }
}
