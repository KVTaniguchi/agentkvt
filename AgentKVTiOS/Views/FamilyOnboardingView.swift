import SwiftUI
import SwiftData
import ManagerCore

/// First-run: explain family iCloud and create the first in-app profile.
struct FamilyOnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var profileStore: FamilyProfileStore

    @State private var displayName = ""
    @State private var symbol = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let backendSync = IOSBackendSyncService()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        """
                        AgentKVT syncs through iCloud using your family’s shared Apple ID.

                        On this device: open Settings, tap your name, and sign in to iCloud with that Apple ID. This app does not ask for your Apple ID password — iOS handles sign-in in Settings.

                        Personal Apple IDs and their data are not accessed; only what you add in AgentKVT is shared.
                        """
                    )
                    .font(.body)
                    .foregroundStyle(.primary)
                } header: {
                    Text("Family iCloud")
                }

                Section {
                    TextField("Your name", text: $displayName)
                        .textContentType(.name)
                    TextField("Optional emoji or short tag", text: $symbol)
                } header: {
                    Text("Your profile")
                } footer: {
                    Text("Each family member creates a profile here. It labels your messages and uploads in the shared database.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Welcome")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Continue") { createProfile() }
                        .disabled(isSaving || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func createProfile() {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let sym = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        IOSRuntimeLog.log("[FamilyOnboardingView] Creating initial family member '\(name)' symbol='\(sym)'")
        isSaving = true
        Task { @MainActor in
            do {
                let member = try await backendSync.createFamilyMember(
                    displayName: name,
                    symbol: sym,
                    modelContext: modelContext
                )
                profileStore.selectProfile(member.id)
                errorMessage = nil
                IOSRuntimeLog.log("[FamilyOnboardingView] Created initial family member id=\(member.id.uuidString)")
            } catch {
                errorMessage = error.localizedDescription
                IOSRuntimeLog.log("[FamilyOnboardingView] Failed to create initial family member '\(name)': \(error)")
            }
            isSaving = false
        }
    }
}

/// Shown when profiles exist but none is selected (e.g. new device or cleared defaults).
/// Add another person after the first profile exists.
struct AddFamilyMemberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var displayName = ""
    @State private var symbol = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let backendSync = IOSBackendSyncService()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $displayName)
                    TextField("Optional emoji or short tag", text: $symbol)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("New profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Adding…" : "Add") { save() }
                        .disabled(isSaving || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let sym = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        IOSRuntimeLog.log("[AddFamilyMemberSheet] Creating family member '\(name)' symbol='\(sym)'")
        isSaving = true
        Task { @MainActor in
            do {
                _ = try await backendSync.createFamilyMember(
                    displayName: name,
                    symbol: sym,
                    modelContext: modelContext
                )
                IOSRuntimeLog.log("[AddFamilyMemberSheet] Created family member '\(name)'")
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                IOSRuntimeLog.log("[AddFamilyMemberSheet] Failed to create family member '\(name)': \(error)")
            }
            isSaving = false
        }
    }
}

struct ProfilePickerView: View {
    let members: [FamilyMember]
    @ObservedObject var profileStore: FamilyProfileStore

    var body: some View {
        NavigationStack {
            List(members, id: \.id) { m in
                Button {
                    profileStore.selectProfile(m.id)
                } label: {
                    HStack {
                        if !m.symbol.isEmpty {
                            Text(m.symbol)
                        }
                        VStack(alignment: .leading) {
                            Text(m.displayName)
                                .font(.headline)
                            Text("Member since \(m.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Who’s using the app?")
        }
    }
}
