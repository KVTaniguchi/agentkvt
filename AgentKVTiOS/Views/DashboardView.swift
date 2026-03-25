import SwiftUI
import SwiftData
import ManagerCore

/// Dashboard: observe ActionItem and render dynamic AppIntentButtons. No chat.
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
            InboundFilesView(files: inboundFiles, familyMembers: familyMembers)
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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Upload File", systemImage: "square.and.arrow.up")
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

    private var missionsById: [UUID: MissionDefinition] {
        Dictionary(uniqueKeysWithValues: missions.map { ($0.id, $0) })
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items.filter { !$0.isHandled }, id: \.id) { item in
                    NavigationLink {
                        ActionItemDetailView(
                            item: item,
                            mission: item.missionId.flatMap { missionsById[$0] }
                        ) {
                            item.isHandled = true
                            try? modelContext.save()
                        }
                    } label: {
                        ActionItemRow(item: item, missionName: item.missionId.flatMap { missionsById[$0]?.missionName })
                    }
                }
            }
            .navigationTitle("Actions")
            .emptyState(items.isEmpty, message: "No action items. Missions on the Mac will create them.")
        }
    }
}

struct ActionItemRow: View {
    let item: ActionItem
    let missionName: String?

    private var route: IntentRoute { IntentRoute.route(for: item) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: route.iconName)
                .foregroundStyle(.tint)
                .frame(width: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let missionName {
                    Label(missionName, systemImage: "sparkles.rectangle.stack")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                Text(item.systemIntent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    var body: some View {
        List {
            if !item.isHandled {
                Section {
                    DynamicIntentButton(item: item) {
                        onMarkHandled()
                        dismiss()
                    }
                    .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
            }

            Section("Action") {
                LabeledContent("Title", value: item.title)
                LabeledContent("Intent", value: item.systemIntent)
                LabeledContent("Created") {
                    Text(item.timestamp, style: .date)
                }
                LabeledContent("Handled") {
                    Text(item.isHandled ? "Yes" : "No")
                }
            }

            Section("Mission") {
                if let mission {
                    LabeledContent("Name", value: mission.missionName)
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
            }

            if let payloadText {
                Section("Payload") {
                    ScrollView(.horizontal) {
                        Text(payloadText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .navigationTitle("Action Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !item.isHandled {
                    Button("Mark Done") {
                        onMarkHandled()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct InboundFilesView: View {
    let files: [InboundFile]
    let familyMembers: [FamilyMember]

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
}
