import SwiftUI
import SwiftData
import ManagerCore

/// Dashboard: main iOS surface for objectives, actions, missions, logs, files, and chat.
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileStore: FamilyProfileStore
    @Query(sort: \FamilyMember.createdAt, order: .forward) private var familyMembers: [FamilyMember]
    @Query(sort: \InboundFile.timestamp, order: .reverse) private var inboundFiles: [InboundFile]
    @State private var selectedTab = 0
    @State private var isImporterPresented = false
    @State private var importError: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            ObjectivesDashboardView()
                .tabItem { Label("Objectives", systemImage: "target") }
                .tag(0)
            ActionItemsList()
                .tabItem { Label("Actions", systemImage: "square.grid.2x2") }
                .tag(1)
            MissionListView()
                .tabItem { Label("Missions", systemImage: "list.bullet") }
                .tag(2)
            LifeContextView()
                .tabItem { Label("Context", systemImage: "person.crop.circle") }
                .tag(3)
            AgentLogView()
                .tabItem { Label("Log", systemImage: "doc.text.magnifyingglass") }
                .tag(4)
            ChatView()
                .tabItem { Label("Chat", systemImage: "message") }
                .tag(5)
            InboundFilesView(
                files: inboundFiles,
                familyMembers: familyMembers,
                isImporterPresented: $isImporterPresented
            )
                .tabItem { Label("Files", systemImage: "doc") }
                .tag(6)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf, .plainText, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                // Picked URLs are security-scoped; reading without this yields "permission" errors.
                guard url.startAccessingSecurityScopedResource() else {
                    importError = "Failed to import file: Could not access the selected file."
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let data = try Data(contentsOf: url)
                    let inbound = InboundFile(
                        fileName: url.lastPathComponent,
                        fileData: data,
                        uploadedByProfileId: profileStore.currentProfileId
                    )
                    modelContext.insert(inbound)
                    try modelContext.save()
                } catch {
                    importError = "Failed to import file: \(error.localizedDescription)"
                }
            case .failure(let error):
                importError = "File import failed: \(error.localizedDescription)"
            }
        }
        .alert("File Import Error", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            if let importError {
                Text(importError)
            }
        }
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
                if let missionId = item.sourceMissionId {
                    Text("Mission …\(missionId.uuidString.suffix(8))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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

                    if let missionId = item.sourceMissionId {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Source Mission")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("…\(missionId.uuidString.suffix(8))")
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                    }

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
    let files: [InboundFile]
    let familyMembers: [FamilyMember]
    @Binding var isImporterPresented: Bool

    private let staleInterval: TimeInterval = 5 * 60 // 5 minutes

    private func uploaderName(for file: InboundFile) -> String? {
        guard let id = file.uploadedByProfileId,
              let m = familyMembers.first(where: { $0.id == id }) else { return nil }
        return m.displayName
    }

    private func status(for file: InboundFile) -> (label: String, color: Color, note: String?) {
        if file.isProcessed {
            return ("Processed", .green, nil)
        }
        let age = Date().timeIntervalSince(file.timestamp)
        if age > staleInterval {
            return ("Pending", .orange, "Waiting for Mac to sync…")
        }
        return ("Pending", .orange, nil)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(files, id: \.id) { file in
                    let s = status(for: file)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.fileName)
                                .font(.headline)
                            Text(file.timestamp, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let who = uploaderName(for: file) {
                                Text("From \(who)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let note = s.note {
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(s.label)
                            .font(.caption2)
                            .padding(6)
                            .background(s.color.opacity(0.15))
                            .foregroundStyle(s.color)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .navigationTitle("Inbound Files")
            .emptyState(files.isEmpty, message: "Upload PDFs, TXTs, or CSVs to share with your Mac agent.")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Add File", systemImage: "plus")
                    }
                    .accessibilityIdentifier(InboundFilesImportUI.addButtonAccessibilityIdentifier)
                }
            }
            .familyProfileToolbar()
        }
    }
}

struct FamilyProfileToolbarMenu: View {
    @EnvironmentObject private var profileStore: FamilyProfileStore
    @Query(sort: \FamilyMember.createdAt, order: .forward) private var familyMembers: [FamilyMember]

    let onAddFamilyMember: () -> Void

    private var currentProfileLabel: String {
        guard let id = profileStore.currentProfileId,
              let member = familyMembers.first(where: { $0.id == id }) else {
            return "Profile"
        }
        return member.symbol.isEmpty ? member.displayName : "\(member.symbol) \(member.displayName)"
    }

    var body: some View {
        Menu {
            ForEach(familyMembers, id: \.id) { member in
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
