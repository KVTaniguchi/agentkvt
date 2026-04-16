import SwiftUI
import UniformTypeIdentifiers

/// Dashboard: main iOS surface for server-backed family data.
struct DashboardView: View {
    @Environment(InboundFilesStore.self) private var inboundFilesStore
    @EnvironmentObject private var profileStore: FamilyProfileStore

    @State private var selectedTab = 0
    @State private var isImporterPresented = false
    @State private var importErrorMessage: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            ObjectivesDashboardView()
                .tabItem { Label("Objectives", systemImage: "target") }
                .tag(0)

            LifeContextView()
                .tabItem { Label("Context", systemImage: "person.crop.circle") }
                .tag(3)
            ChatView()
                .tabItem { Label("Chat", systemImage: "message") }
                .tag(4)
            InboundFilesView(isImporterPresented: $isImporterPresented)
                .tabItem { Label("Files", systemImage: "doc") }
                .tag(5)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleImport(result) }
        }
        .alert("Could Not Upload File", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "The selected file could not be uploaded.")
        }
    }

    @MainActor
    private func handleImport(_ result: Result<[URL], Error>) async {
        let fileURL: URL
        switch result {
        case .success(let urls):
            guard let selectedURL = urls.first else { return }
            fileURL = selectedURL
        case .failure(let error):
            importErrorMessage = error.localizedDescription
            IOSRuntimeLog.log("[DashboardView] File importer failed: \(error)")
            return
        }

        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let fileData = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            let uploaded = try await inboundFilesStore.uploadFile(
                fileName: fileURL.lastPathComponent,
                contentType: resolvedContentType(for: fileURL),
                fileData: fileData,
                uploadedByProfileId: profileStore.currentProfileId
            )
            IOSRuntimeLog.log("[DashboardView] Uploaded inbound file id=\(uploaded.id.uuidString)")
        } catch {
            importErrorMessage = error.localizedDescription
            IOSRuntimeLog.log("[DashboardView] Inbound file upload failed: \(error)")
        }
    }

    private func resolvedContentType(for fileURL: URL) -> String? {
        if let values = try? fileURL.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = values.contentType?.preferredMIMEType {
            return contentType
        }

        let pathExtension = fileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pathExtension.isEmpty else { return nil }
        return UTType(filenameExtension: pathExtension)?.preferredMIMEType
    }
}


/// UI constants for Inbound Files (accessibility / UI tests).
enum InboundFilesImportUI {
    static let addButtonAccessibilityIdentifier = "inbound-files-add-items"
}

struct InboundFilesView: View {
    @Environment(InboundFilesStore.self) private var store
    @Environment(FamilyMembersStore.self) private var familyMembersStore

    @Binding var isImporterPresented: Bool

    private let staleInterval: TimeInterval = 5 * 60

    private func uploaderName(for file: IOSBackendInboundFile) -> String? {
        guard let id = file.uploadedByProfileId,
              let member = familyMembersStore.members.first(where: { $0.id == id }) else {
            return nil
        }
        return member.displayName
    }

    private func status(for file: IOSBackendInboundFile) -> (label: String, color: Color, note: String?) {
        if file.isProcessed {
            return ("Processed", .green, nil)
        }
        let age = Date().timeIntervalSince(file.timestamp)
        if age > staleInterval {
            return ("Pending", .orange, "Waiting for the Mac runner to process this file.")
        }
        return ("Pending", .orange, nil)
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage = store.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(store.files, id: \.id) { file in
                    let fileStatus = status(for: file)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.fileName)
                                .font(.headline)
                            Text(file.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let uploaderName = uploaderName(for: file) {
                                Text("From \(uploaderName)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let note = fileStatus.note {
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(fileStatus.label)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(fileStatus.color.opacity(0.15))
                            .foregroundStyle(fileStatus.color)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Inbound Files")
            .refreshable {
                await store.refresh()
            }
            .overlay {
                if store.isLoading && store.files.isEmpty {
                    ProgressView("Loading files…")
                }
            }
            .emptyState(
                store.files.isEmpty && !store.isLoading,
                message: "Upload PDFs, text files, or spreadsheets to hand them to the family server and Mac runner."
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Add File", systemImage: "plus")
                    }
                    .disabled(store.isUploading)
                    .accessibilityIdentifier(InboundFilesImportUI.addButtonAccessibilityIdentifier)
                }
            }
            .familyProfileToolbar()
        }
        .task {
            await store.refresh()
        }
    }
}

struct FamilyProfileToolbarMenu: View {
    @EnvironmentObject private var profileStore: FamilyProfileStore
    @Environment(FamilyMembersStore.self) private var familyMembersStore

    let onAddFamilyMember: () -> Void

    private var currentProfileLabel: String {
        guard let id = profileStore.currentProfileId,
              let member = familyMembersStore.members.first(where: { $0.id == id }) else {
            return "Profile"
        }
        guard let symbol = member.symbol?.trimmingCharacters(in: .whitespacesAndNewlines), !symbol.isEmpty else {
            return member.displayName
        }
        return "\(symbol) \(member.displayName)"
    }

    var body: some View {
        Menu {
            ForEach(familyMembersStore.members, id: \.id) { member in
                Button {
                    profileStore.selectProfile(member.id)
                } label: {
                    if member.id == profileStore.currentProfileId {
                        Label(member.displayName, systemImage: "checkmark")
                    } else {
                        Text(member.displayName)
                    }
                }
            }
            Divider()
            Button("Add family member…") {
                onAddFamilyMember()
            }
        } label: {
            Label(currentProfileLabel, systemImage: "person.crop.circle")
        }
        .accessibilityIdentifier("family-profile-menu")
    }
}

struct FamilyProfileToolbarModifier: ViewModifier {
    @State private var showAddFamilyMember = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    FamilyProfileToolbarMenu {
                        showAddFamilyMember = true
                    }
                }
            }
            .sheet(isPresented: $showAddFamilyMember) {
                AddFamilyMemberSheet()
            }
    }
}

extension View {
    @ViewBuilder
    func emptyState(_ isEmpty: Bool, message: String) -> some View {
        if isEmpty {
            ContentUnavailableView("No items", systemImage: "tray", description: Text(message))
        } else {
            self
        }
    }

    func familyProfileToolbar() -> some View {
        modifier(FamilyProfileToolbarModifier())
    }
}
