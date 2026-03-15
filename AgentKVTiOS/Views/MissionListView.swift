import SwiftUI
import SwiftData
import ManagerCore

/// Mission authoring: create/edit MissionDefinition (name, prompt, schedule, allowed tools).
struct MissionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MissionDefinition.updatedAt, order: .reverse) private var missions: [MissionDefinition]
    @State private var showAddMission = false

    private static let knownToolIds = ["write_action_item", "web_search_and_fetch", "headless_browser_scout", "send_notification_email", "github_agent", "fetch_bee_ai_context", "incoming_email_trigger"]

    var body: some View {
        NavigationStack {
            List {
                ForEach(missions, id: \.id) { mission in
                    NavigationLink {
                        MissionEditView(mission: mission, toolIds: Self.knownToolIds) { name, prompt, schedule, tools in
                            mission.missionName = name
                            mission.systemPrompt = prompt
                            mission.triggerSchedule = schedule
                            mission.allowedMCPTools = tools
                            mission.updatedAt = Date()
                            try? modelContext.save()
                        }
                    } label: {
                        MissionRow(mission: mission)
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
                MissionEditView(mission: nil, toolIds: Self.knownToolIds) { name, prompt, schedule, tools in
                    let m = MissionDefinition(missionName: name, systemPrompt: prompt, triggerSchedule: schedule, allowedMCPTools: tools)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mission.missionName)
                .font(.headline)
            Text(mission.triggerSchedule)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(mission.isEnabled ? "On" : "Off")
                .font(.caption2)
                .foregroundStyle(mission.isEnabled ? .green : .secondary)
        }
    }
}

struct MissionEditView: View {
    let mission: MissionDefinition?
    let toolIds: [String]
    let onSave: (String, String, String, [String]) -> Void

    @State private var name: String = ""
    @State private var systemPrompt: String = ""
    @State private var triggerSchedule: String = "daily|08:00"
    @State private var selectedToolIds: Set<String> = []
    @Environment(\.dismiss) private var dismiss

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
                }
                Section("Allowed tools") {
                    ForEach(toolIds, id: \.self) { id in
                        Toggle(id, isOn: Binding(
                            get: { selectedToolIds.contains(id) },
                            set: { if $0 { selectedToolIds.insert(id) } else { selectedToolIds.remove(id) } }
                        ))
                    }
                }
            }
            .navigationTitle(mission == nil ? "New Mission" : "Edit Mission")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, systemPrompt, triggerSchedule, Array(selectedToolIds).sorted())
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                if let m = mission {
                    name = m.missionName
                    systemPrompt = m.systemPrompt
                    triggerSchedule = m.triggerSchedule
                    selectedToolIds = Set(m.allowedMCPTools)
                }
            }
        }
    }
}
