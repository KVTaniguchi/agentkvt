import Foundation
import Observation

@Observable
final class WorkspaceStore {
    private(set) var workspace: IOSBackendWorkspace?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let sync: IOSBackendSyncService

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
            let bootstrap = try await sync.fetchBootstrapRemote()
            self.workspace = bootstrap.workspace
        } catch {
            errorMessage = error.localizedDescription
            IOSRuntimeLog.log("[WorkspaceStore] Refresh failed: \(error)")
        }
    }

    @MainActor
    func replaceWorkspace(_ workspace: IOSBackendWorkspace?) {
        self.workspace = workspace
    }
}
