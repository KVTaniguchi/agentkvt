import Foundation

enum MissionExecutionContext {
    struct Context: Sendable {
        let missionId: UUID
        let missionName: String
        let objectiveId: UUID?
        let taskId: UUID?
        let workUnitId: UUID?
        let workerLabel: String?
    }

    @TaskLocal
    static var current: Context?
}
