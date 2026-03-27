import SwiftUI
import SwiftData
import ManagerCore

/// Routes between onboarding, profile selection, and the main dashboard.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyMember.createdAt, order: .forward) private var members: [FamilyMember]
    @EnvironmentObject private var profileStore: FamilyProfileStore
    @State private var hasAttemptedBackendBootstrap = false

    private let backendSync = IOSBackendSyncService()

    var body: some View {
        Group {
            if backendSync.isEnabled && !hasAttemptedBackendBootstrap {
                ProgressView("Syncing with server…")
            } else if members.isEmpty {
                FamilyOnboardingView(profileStore: profileStore)
            } else if !profileStore.hasValidSelection(members: members) {
                ProfilePickerView(members: members, profileStore: profileStore)
            } else {
                DashboardView()
            }
        }
        .task {
            guard backendSync.isEnabled, !hasAttemptedBackendBootstrap else {
                hasAttemptedBackendBootstrap = true
                return
            }
            await backendSync.bootstrap(modelContext: modelContext)
            hasAttemptedBackendBootstrap = true
        }
    }
}
