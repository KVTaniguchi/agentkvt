import SwiftUI
import SwiftData
import ManagerCore

/// Dashboard: main iOS surface for actions, missions, logs, files, and chat.
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileStore: FamilyProfileStore
    @Query(sort: \FamilyMember.createdAt, order: .forward) private var familyMembers: [FamilyMember]
    @Query(sort: \ActionItem.timestamp, order: .reverse) private var actionItems: [ActionItem]
    @Query(sort: \InboundFile.timestamp, order: .reverse) private var inboundFiles: [InboundFile]
    @State private var selectedTab = 0
    @State private var isImporterPresented = false
    @State private var importError: String?
    @State private var showAddFamilyMember = false

    private var currentProfileLabel: String {
        guard let id = profileStore.currentProfileId,
              let m = familyMembers.first(where: { $0.id == id }) else {
            return "Profile"
        }
        return m.symbol.isEmpty ? m.displayName : "\(m.symbol) \(m.displayName)"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ActionItemsList(items: actionItems)
                .tabItem { Label("Actions", systemImage: "square.grid.2x2") }
                .tag(0)
            MissionListView()
                .tabItem { Label("Missions", systemImage: "list.bullet") }
                .tag(1)
            LifeContextView()
                .tabItem { Label("Context", systemImage: "person.crop.circle") }
                .tag(2)
            AgentLogView()
                .tabItem { Label("Log", systemImage: "doc.text.magnifyingglass") }
                .tag(3)
            ChatView()
                .tabItem { Label("Chat", systemImage: "message") }
                .tag(4)
            InboundFilesView(
                files: inboundFiles,
                familyMembers: familyMembers,
                isImporterPresented: $isImporterPresented
            )
                .tabItem { Label("Files", systemImage: "doc") }
                .tag(5)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    ForEach(familyMembers, id: \.id) { m in
                        Button {
                            profileStore.selectProfile(m.id)
                        } label: {
                            if m.id == profileStore.currentProfileId {
                                Label(m.displayName, systemImage: "checkmark")
                            } else {
                                Text(m.displayName)
                            }
                        }
                    }
                    Divider()
                    Button("Add family member…") { showAddFamilyMember = true }
                } label: {
                    Label(currentProfileLabel, systemImage: "person.crop.circle")
                }
            }
        }
        .sheet(isPresented: $showAddFamilyMember) {
            AddFamilyMemberSheet()
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf, .plainText, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
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
    let items: [ActionItem]
    @Environment(\.modelContext) private var modelContext
    @Query private var missions: [MissionDefinition]
    @State private var handleErrorMessage: String?

    private let backendSync = IOSBackendSyncService()

    private var missionsById: [UUID: MissionDefinition] {
        Dictionary(uniqueKeysWithValues: missions.map { ($0.id, $0) })
    }

    private var visibleItems: [ActionItem] {
        items.filter { !$0.isHandled }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(visibleItems, id: \.id) { item in
                    NavigationLink {
                        ActionItemDetailView(
                            item: item,
                            mission: item.missionId.flatMap { missionsById[$0] }
                        ) {
                            Task { @MainActor in
                                await markHandled(item)
                            }
                        }
                    } label: {
                        ActionItemRow(item: item, missionName: item.missionId.flatMap { missionsById[$0]?.missionName })
                    }
                }
            }
            .navigationTitle("Actions")
            .refreshable {
                await backendSync.syncActionItems(modelContext: modelContext)
            }
            .emptyState(visibleItems.isEmpty, message: "No action items. Missions on the Mac will create them.")
            .familyProfileToolbar()
        }
        .task {
            await backendSync.syncActionItems(modelContext: modelContext)
        }
        .alert("Could Not Mark Action Done", isPresented: Binding(
            get: { handleErrorMessage != nil },
            set: { if !$0 { handleErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                handleErrorMessage = nil
            }
        } message: {
            Text(handleErrorMessage ?? "The action item could not be updated.")
        }
    }

    @MainActor
    private func markHandled(_ item: ActionItem) async {
        guard !item.isHandled else { return }

        let originalValue = item.isHandled
        item.isHandled = true
        try? modelContext.save()

        do {
            try await backendSync.handleActionItem(item, modelContext: modelContext)
        } catch {
            item.isHandled = originalValue
            try? modelContext.save()
            handleErrorMessage = error.localizedDescription
            IOSRuntimeLog.log("[ActionItemsList] Failed to mark action item \(item.id.uuidString) handled: \(error)")
        }
    }
}

struct ActionItemRow: View {
    let item: ActionItem
    let missionName: String?

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
                if let missionName {
                    Text(missionName)
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

struct ActionItemDetailView: View {
    let item: ActionItem
    let mission: MissionDefinition?
    let onMarkHandled: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var payloadText: String? {
        guard let payloadData = item.payloadData, !payloadData.isEmpty else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: payloadData),
           let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
           let pretty = String(data: prettyData, encoding: .utf8) {
            return pretty
        }
        return String(data: payloadData, encoding: .utf8)
    }

    private var missionStatus: String {
        guard let mission else { return "Unknown mission" }
        return mission.isEnabled ? "Enabled" : "Disabled"
    }

    private var createdAtText: String {
        item.timestamp.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let mission {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("From Mission")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(mission.missionName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text("Source mission unavailable")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Label(createdAtText, systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            if !item.isHandled {
                Section {
                    DynamicIntentButton(item: item)
                    .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
                } footer: {
                    Text("Use the action above to follow the agent's recommendation. Tap Done after you've handled it or want to clear it from the queue.")
                }
            }

            Section {
                DisclosureGroup("Technical Details") {
                    LabeledContent("Intent", value: item.systemIntent)
                    LabeledContent("Handled") {
                        Text(item.isHandled ? "Yes" : "No")
                    }

                    if let mission {
                        LabeledContent("Schedule", value: mission.triggerSchedule)
                        LabeledContent("Status", value: missionStatus)
                        if let lastRunAt = mission.lastRunAt {
                            LabeledContent("Last Run") {
                                Text(lastRunAt, style: .relative)
                            }
                        }
                        if !mission.allowedMCPTools.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Allowed Tools")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(mission.allowedMCPTools.joined(separator: ", "))
                                    .font(.body)
                            }
                            .padding(.vertical, 4)
                        }
                    } else {
                        Text("This action is not currently linked to a loaded mission record.")
                            .foregroundStyle(.secondary)
                    }

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
                            .frame(maxWidth: .infinity, alignment: .leading)
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
