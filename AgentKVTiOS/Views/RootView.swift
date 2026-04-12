import SwiftUI

/// Routes between onboarding, profile selection, and the main dashboard.
struct RootView: View {
    @EnvironmentObject private var profileStore: FamilyProfileStore
    @Environment(FamilyMembersStore.self) private var familyMembersStore
    @Environment(LifeContextStore.self) private var lifeContextStore
    @Environment(AgentLogsStore.self) private var agentLogsStore
    @Environment(ActionsStore.self) private var actionsStore
    @State private var bootstrapState: BackendBootstrapState = .idle

    @State private var backendSync = IOSBackendSyncService()

    var body: some View {
        Group {
            switch RootViewStateResolver.destination(
                isBackendEnabled: backendSync.isEnabled,
                bootstrapState: bootstrapState,
                memberCount: familyMembersStore.members.count,
                hasValidSelection: profileStore.hasValidSelection(
                    memberIDs: familyMembersStore.members.map(\.id)
                )
            ) {
            case .loading:
                ProgressView("Syncing with server…")
            case .backendError(let message):
                BackendBootstrapErrorView(
                    backendURL: backendSync.settings.apiBaseURL?.absoluteString,
                    message: message,
                    retry: { Task { await bootstrapFromBackend(force: true) } },
                    onSaveURL: { newURL in
                        UserDefaults.standard.set(newURL, forKey: "AGENTKVT_API_BASE_URL")
                        backendSync = IOSBackendSyncService()
                        Task { await bootstrapFromBackend(force: true) }
                    }
                )
            case .onboarding:
                FamilyOnboardingView(profileStore: profileStore)
            case .profilePicker:
                ProfilePickerView(members: familyMembersStore.members, profileStore: profileStore)
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
            let snapshot = try await backendSync.fetchBootstrapRemote()
            familyMembersStore.replaceMembers(snapshot.familyMembers)
            lifeContextStore.replaceEntries(snapshot.lifeContextEntries)
            agentLogsStore.replaceLogs(snapshot.agentLogs)
            actionsStore.replaceItems(snapshot.actionItems)
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
    let onSaveURL: (String) -> Void

    @State private var urlInput: String = ""

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

                VStack(alignment: .leading, spacing: 8) {
                    Text("Server URL")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField("http://192.168.1.x:3000", text: $urlInput)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Save & Connect") {
                        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSaveURL(trimmed)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Button("Retry") {
                    retry()
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()
            .navigationTitle("Welcome")
            .onAppear {
                urlInput = backendURL ?? ""
            }
        }
    }
}
