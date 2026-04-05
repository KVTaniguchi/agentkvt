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
            ActionItemsList()
                .tabItem { Label("Actions", systemImage: "square.grid.2x2") }
                .tag(1)

            LifeContextView()
                .tabItem { Label("Context", systemImage: "person.crop.circle") }
                .tag(3)
            AgentLogView()
                .tabItem { Label("Log", systemImage: "doc.text.magnifyingglass") }
                .tag(4)
            ChatView()
                .tabItem { Label("Chat", systemImage: "message") }
                .tag(5)
            InboundFilesView(isImporterPresented: $isImporterPresented)
                .tabItem { Label("Files", systemImage: "doc") }
                .tag(6)
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

struct ActionItemsList: View {
    @Environment(ActionsStore.self) private var store
    @State private var handleErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.items, id: \.id) { item in
                    NavigationLink {
                        RemoteActionItemDetailView(item: item) {
                            Task { await markHandled(item) }
                        }
                    } label: {
                        RemoteActionItemRow(item: item)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            Task { await markHandled(item) }
                        } label: {
                            Label("Mark Done", systemImage: "checkmark.circle.fill")
                        }
                        .tint(.green)
                    }
                    .contextMenu {
                        Button {
                            Task { await markHandled(item) }
                        } label: {
                            Label("Mark Done", systemImage: "checkmark.circle")
                        }
                    }
                }
            }
            .navigationTitle("Actions")
            .refreshable { await store.refresh() }
            .overlay {
                if store.isLoading && store.items.isEmpty {
                    ProgressView()
                }
            }
            .emptyState(store.items.isEmpty && !store.isLoading,
                        message: "No action items. Missions on the Mac will create them.")
            .familyProfileToolbar()
        }
        .task { await store.refresh() }
        .alert("Could Not Mark Action Done", isPresented: Binding(
            get: { handleErrorMessage != nil },
            set: { if !$0 { handleErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { handleErrorMessage = nil }
        } message: {
            Text(handleErrorMessage ?? "The action item could not be updated.")
        }
    }

    @MainActor
    private func markHandled(_ item: IOSBackendActionItem) async {
        do {
            try await store.markHandled(item)
        } catch {
            handleErrorMessage = error.localizedDescription
            IOSRuntimeLog.log("[ActionItemsList] markHandled failed for \(item.id): \(error)")
        }
    }
}

struct RemoteActionItemRow: View {
    let item: IOSBackendActionItem

    private var route: IntentRoute { IntentRoute.route(for: item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Label(route.label, systemImage: route.iconName)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(route.badgeColor.opacity(0.85))
                    .clipShape(Capsule())
            }
            Text(item.timestamp, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct RemoteActionItemDetailView: View {
    let item: IOSBackendActionItem
    let onMarkHandled: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var payloadText: String? {
        guard !item.payloadJson.isEmpty else { return nil }
        let obj = item.payloadJson.mapValues { $0.foundationObject }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
              let pretty = String(data: data, encoding: .utf8) else { return nil }
        return pretty
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(item.timestamp.formatted(date: .abbreviated, time: .shortened),
                          systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            if !item.isHandled {
                Section {
                    RemoteDynamicIntentButton(item: item)
                        .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
                } footer: {
                    Text("Use the action above to follow the agent's recommendation. Tap Done after you've handled it.")
                }
            }

            Section {
                DisclosureGroup("Technical Details") {
                    LabeledContent("Intent", value: item.systemIntent)
                    LabeledContent("Handled", value: item.isHandled ? "Yes" : "No")
                    LabeledContent("Created by", value: item.createdBy ?? "agent")

                    if let payloadText {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Payload")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal) {
                                Text(payloadText)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Review Action")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !item.isHandled {
                    Button("Done") {
                        onMarkHandled()
                        dismiss()
                    }
                }
            }
        }
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
