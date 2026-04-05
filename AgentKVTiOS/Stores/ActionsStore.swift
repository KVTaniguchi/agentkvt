import Foundation
import Observation

protocol ActionItemsSyncing {
    var isEnabled: Bool { get }
    func fetchUnhandledActionItemsRemote() async throws -> [IOSBackendActionItem]
    func handleActionItemRemote(id: UUID) async throws
}

extension IOSBackendSyncService: ActionItemsSyncing {
    func fetchUnhandledActionItemsRemote() async throws -> [IOSBackendActionItem] {
        try await fetchActionItemsRemote(isHandled: false)
    }
}

@Observable
final class ActionsStore {
    private(set) var items: [IOSBackendActionItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let sync: any ActionItemsSyncing
    @ObservationIgnored private var locallyHandledItemIDs: Set<UUID> = []

    init(sync: any ActionItemsSyncing = IOSBackendSyncService()) {
        self.sync = sync
    }

    @MainActor
    func refresh() async {
        guard sync.isEnabled else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            replaceItems(try await sync.fetchUnhandledActionItemsRemote())
        } catch {
            errorMessage = error.localizedDescription
            IOSRuntimeLog.log("[ActionsStore] Refresh failed: \(error)")
        }
    }

    @MainActor
    func replaceItems(_ remoteItems: [IOSBackendActionItem]) {
        items = remoteItems.filter { item in
            !item.isHandled && !locallyHandledItemIDs.contains(item.id)
        }
        errorMessage = nil
    }

    /// Marks an item handled on the server and removes it from the local list.
    /// Throws on network failure so the caller can present an alert and revert UI.
    @MainActor
    func markHandled(_ item: IOSBackendActionItem) async throws {
        try await sync.handleActionItemRemote(id: item.id)
        locallyHandledItemIDs.insert(item.id)
        items.removeAll { $0.id == item.id }
    }
}
