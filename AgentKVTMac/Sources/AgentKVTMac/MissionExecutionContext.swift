import Foundation

enum MissionExecutionContext {
    struct Context: Sendable {
        let missionId: UUID
        let missionName: String
    }

    @TaskLocal
    static var current: Context?
}
