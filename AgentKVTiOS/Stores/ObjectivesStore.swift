import Foundation
import Observation

@Observable
final class ObjectivesStore {
    private(set) var objectives: [IOSBackendObjective] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let sync: IOSBackendSyncService

    init(sync: IOSBackendSyncService = IOSBackendSyncService()) {
        self.sync = sync
    }

    @MainActor
    func refresh() async {
        guard sync.isEnabled else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            objectives = try await sync.fetchObjectivesRemote()
        } catch {
            errorMessage = error.localizedDescription
            IOSRuntimeLog.log("[ObjectivesStore] Refresh failed: \(error)")
        }
    }

    /// Creates an objective on the server and prepends it to the local list.
    @MainActor
    func createObjective(goal: String, status: String = "active") async throws -> IOSBackendObjective {
        let objective = try await sync.createObjectiveRemote(goal: goal, status: status, priority: 0)
        objectives.insert(objective, at: 0)
        return objective
    }

    /// Fetches the full detail (tasks + snapshots) for a single objective.
    func fetchDetail(for id: UUID) async throws -> IOSBackendObjectiveDetail {
        try await sync.fetchObjectiveDetailRemote(id: id)
    }
}
