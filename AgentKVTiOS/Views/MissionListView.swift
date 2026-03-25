import SwiftUI
import SwiftData
import ManagerCore

/// Mission authoring: create/edit MissionDefinition (name, prompt, schedule, allowed tools).
struct MissionListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileStore: FamilyProfileStore
    @Query(sort: \MissionDefinition.updatedAt, order: .reverse) private var missions: [MissionDefinition]
    @Query(sort: \FamilyMember.createdAt, order: .forward) private var familyMembers: [FamilyMember]
    @State private var showAddMission = false

    private static let knownToolIds = ["write_action_item", "web_search_and_fetch", "headless_browser_scout", "send_notification_email", "github_agent", "fetch_bee_ai_context", "incoming_email_trigger"]

    var body: some View {
        NavigationStack {
            List {
                ForEach(missions, id: \.id) { mission in
                    NavigationLink {
                        MissionEditView(
                            mission: mission,
                            toolIds: Self.knownToolIds,
                            familyMembers: familyMembers,
                            defaultOwnerProfileId: profileStore.currentProfileId
                        ) { name, prompt, schedule, tools, ownerProfileId in
                            mission.missionName = name
                            mission.systemPrompt = prompt
                            mission.triggerSchedule = schedule
                            mission.allowedMCPTools = tools
                            mission.ownerProfileId = ownerProfileId
                            mission.updatedAt = Date()
                            try? modelContext.save()
                        }
                    } label: {
                        MissionRow(
                            mission: mission,
                            ownerName: mission.ownerProfileId.flatMap { id in
                                familyMembers.first(where: { $0.id == id })?.displayName
                            }
                        )
                    }
                }
            }
            .navigationTitle("Missions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") { showAddMission = true }
                }
            }
            .sheet(isPresented: $showAddMission) {
                MissionEditView(
                    mission: nil,
                    toolIds: Self.knownToolIds,
                    familyMembers: familyMembers,
                    defaultOwnerProfileId: profileStore.currentProfileId
                ) { name, prompt, schedule, tools, ownerProfileId in
                    let m = MissionDefinition(
                        missionName: name,
                        systemPrompt: prompt,
                        triggerSchedule: schedule,
                        allowedMCPTools: tools,
                        ownerProfileId: ownerProfileId
                    )
                    modelContext.insert(m)
                    try? modelContext.save()
                    showAddMission = false
                }
            }
        }
    }
}

struct MissionRow: View {
    let mission: MissionDefinition
    let ownerName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mission.missionName)
                .font(.headline)
            Text(mission.triggerSchedule)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let ownerName {
                Text("Owner: \(ownerName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(mission.isEnabled ? "On" : "Off")
                .font(.caption2)
                .foregroundStyle(mission.isEnabled ? .green : .secondary)
        }
    }
}

struct MissionEditView: View {
    let mission: MissionDefinition?
    let toolIds: [String]
    let familyMembers: [FamilyMember]
    let defaultOwnerProfileId: UUID?
    let onSave: (String, String, String, [String], UUID?) -> Void

    @State private var name: String = ""
    @State private var systemPrompt: String = ""
    @State private var triggerSchedule: String = "daily|08:00"
    @State private var selectedToolIds: Set<String> = []
    @State private var ownerProfileId: UUID?
    @State private var validationMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPrompt: String {
        systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedSchedule: String {
        triggerSchedule.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isScheduleValid: Bool {
        if normalizedSchedule == "webhook" {
            return true
        }
        if normalizedSchedule.range(of: #"^daily\|([01]?\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil {
            return true
        }
        if normalizedSchedule.range(of: #"^weekly\|(sunday|monday|tuesday|wednesday|thursday|friday|saturday)$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private var isFormValid: Bool {
        !trimmedName.isEmpty && !trimmedPrompt.isEmpty && !selectedToolIds.isEmpty && isScheduleValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mission") {
                    TextField("Name", text: $name)
                    TextField("System prompt", text: $systemPrompt, axis: .vertical)
                        .lineLimit(4...8)
                }
                Section("Schedule") {
                    TextField("Trigger (e.g. daily|08:00, weekly|monday)", text: $triggerSchedule)
                    Text("Supported: daily|HH:mm, weekly|weekday, or webhook")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Owner Profile") {
                    Picker("Owner", selection: Binding<UUID?>(
                        get: { ownerProfileId },
                        set: { ownerProfileId = $0 }
                    )) {
                        Text("Unassigned").tag(UUID?.none)
                        ForEach(familyMembers, id: \.id) { member in
                            Text(member.displayName).tag(Optional(member.id))
                        }
                    }
                }
                Section("Allowed tools") {
                    ForEach(toolIds, id: \.self) { id in
                        Toggle(id, isOn: Binding(
                            get: { selectedToolIds.contains(id) },
                            set: { if $0 { selectedToolIds.insert(id) } else { selectedToolIds.remove(id) } }
                        ))
                    }
                }
                if let validationMessage {
                    Section("Validation") {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(mission == nil ? "New Mission" : "Edit Mission")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard isFormValid else {
                            validationMessage = validationError()
                            return
                        }
                        onSave(trimmedName, trimmedPrompt, normalizedSchedule, Array(selectedToolIds).sorted(), ownerProfileId)
                        dismiss()
                    }
                    .disabled(!isFormValid)
                }
            }
            .onAppear {
                if let m = mission {
                    name = m.missionName
                    systemPrompt = m.systemPrompt
                    triggerSchedule = m.triggerSchedule
                    selectedToolIds = Set(m.allowedMCPTools)
                    ownerProfileId = m.ownerProfileId
                } else {
                    ownerProfileId = defaultOwnerProfileId
                }
            }
            .onChange(of: name) { _, _ in validationMessage = nil }
            .onChange(of: systemPrompt) { _, _ in validationMessage = nil }
            .onChange(of: triggerSchedule) { _, _ in validationMessage = nil }
            .onChange(of: selectedToolIds) { _, _ in validationMessage = nil }
        }
    }

    private func validationError() -> String {
        if trimmedName.isEmpty {
            return "Mission name is required."
        }
        if trimmedPrompt.isEmpty {
            return "System prompt is required."
        }
        if selectedToolIds.isEmpty {
            return "Select at least one allowed tool."
        }
        if !isScheduleValid {
            return "Schedule must be daily|HH:mm, weekly|weekday, or webhook."
        }
        return "Mission is invalid."
    }
}
