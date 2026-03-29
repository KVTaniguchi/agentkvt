import Foundation
import Observation

/// Abstraction for remote objective CRUD (enables unit tests with a mock sync layer).
protocol ObjectivesRemoteSyncing: Sendable {
    var isEnabled: Bool { get }
    func fetchObjectivesRemote() async throws -> [IOSBackendObjective]
    func createObjectiveRemote(goal: String, status: String, priority: Int) async throws -> IOSBackendObjective
    func fetchObjectiveDetailRemote(id: UUID) async throws -> IOSBackendObjectiveDetail
    func updateObjectiveRemote(id: UUID, goal: String, status: String, priority: Int) async throws -> IOSBackendObjective
    func deleteObjectiveRemote(id: UUID) async throws
}

extension IOSBackendSyncService: ObjectivesRemoteSyncing {}

@Observable
final class ObjectivesStore {
    private(set) var objectives: [IOSBackendObjective] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let sync: any ObjectivesRemoteSyncing

    init(sync: any ObjectivesRemoteSyncing = IOSBackendSyncService()) {
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

    /// Updates an objective on the server and replaces the local list entry.
    @MainActor
    func updateObjective(id: UUID, goal: String, status: String, priority: Int) async throws -> IOSBackendObjective {
        let updated = try await sync.updateObjectiveRemote(id: id, goal: goal, status: status, priority: priority)
        if let idx = objectives.firstIndex(where: { $0.id == id }) {
            objectives[idx] = updated
        }
        return updated
    }

    /// Deletes an objective on the server and removes it from the local list.
    @MainActor
    func deleteObjective(id: UUID) async throws {
        try await sync.deleteObjectiveRemote(id: id)
        objectives.removeAll { $0.id == id }
    }
}
