import Foundation

enum AgentTaskExecutionContext {
    struct Context: Sendable {
        let taskName: String
        let objectiveId: UUID?
        let taskId: UUID?
        let workUnitId: UUID?
        let workerLabel: String?
    }

    @TaskLocal
    static var current: Context?
}
