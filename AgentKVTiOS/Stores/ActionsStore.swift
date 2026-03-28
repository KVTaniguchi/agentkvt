import Foundation
import Observation

@Observable
final class ActionsStore {
    private(set) var items: [IOSBackendActionItem] = []
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
            items = try await sync.fetchActionItemsRemote()
        } catch {
            errorMessage = error.localizedDescription
            IOSRuntimeLog.log("[ActionsStore] Refresh failed: \(error)")
        }
    }

    /// Marks an item handled on the server and removes it from the local list.
    /// Throws on network failure so the caller can present an alert and revert UI.
    @MainActor
    func markHandled(_ item: IOSBackendActionItem) async throws {
        try await sync.handleActionItemRemote(id: item.id)
        items.removeAll { $0.id == item.id }
    }
}
