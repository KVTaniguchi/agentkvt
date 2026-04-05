import SwiftUI
import SwiftData
import ManagerCore

/// Routes between onboarding, profile selection, and the main dashboard.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyMember.createdAt, order: .forward) private var members: [FamilyMember]
    @EnvironmentObject private var profileStore: FamilyProfileStore
    @State private var bootstrapState: BackendBootstrapState = .idle

    private let backendSync = IOSBackendSyncService()

    var body: some View {
        Group {
            switch RootViewStateResolver.destination(
                isBackendEnabled: backendSync.isEnabled,
                bootstrapState: bootstrapState,
                memberCount: members.count,
                hasValidSelection: profileStore.hasValidSelection(members: members)
            ) {
            case .loading:
                ProgressView("Syncing with server…")
            case .backendError(let message):
                BackendBootstrapErrorView(
                    backendURL: backendSync.settings.apiBaseURL?.absoluteString,
                    message: message,
                    retry: { Task { await bootstrapFromBackend(force: true) } }
                )
            case .onboarding:
                FamilyOnboardingView(profileStore: profileStore)
            case .profilePicker:
                ProfilePickerView(members: members, profileStore: profileStore)
            case .dashboard:
                DashboardView()
            }
        }
        .task {
            await bootstrapFromBackend()
        }
    }

    @MainActor
    private func bootstrapFromBackend(force: Bool = false) async {
        guard backendSync.isEnabled else {
            bootstrapState = .loaded
            return
        }
        guard force || bootstrapState == .idle else { return }

        bootstrapState = .loading
        do {
            try await backendSync.bootstrap(modelContext: modelContext)
            bootstrapState = .loaded
        } catch {
            IOSRuntimeLog.log("[RootView] Backend bootstrap failed: \(error)")
            bootstrapState = .failed(error.localizedDescription)
        }
    }
}

enum BackendBootstrapState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum RootViewDestination: Equatable {
    case loading
    case backendError(String)
    case onboarding
    case profilePicker
    case dashboard
}

struct RootViewStateResolver {
    static func destination(
        isBackendEnabled: Bool,
        bootstrapState: BackendBootstrapState,
        memberCount: Int,
        hasValidSelection: Bool
    ) -> RootViewDestination {
        if isBackendEnabled && bootstrapState == .loading {
            return .loading
        }

        if case .failed(let message) = bootstrapState, memberCount == 0 {
            return .backendError(message)
        }

        if memberCount == 0 {
            return .onboarding
        }

        if !hasValidSelection {
            return .profilePicker
        }

        return .dashboard
    }
}

private struct BackendBootstrapErrorView: View {
    let backendURL: String?
    let message: String
    let retry: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Can’t Reach Server")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("This device now loads family data and objectives from the AgentKVT server. Signing in to iCloud is not required.")
                    .foregroundStyle(.secondary)

                if let backendURL, !backendURL.isEmpty {
                    Text("Backend: \(backendURL)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Retry") {
                    retry()
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .navigationTitle("Welcome")
        }
    }
}
