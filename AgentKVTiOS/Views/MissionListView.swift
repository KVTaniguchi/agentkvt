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
    @State private var deletionErrorMessage: String?
    @State private var runNowErrorMessage: String?
    @State private var runNowConfirmationMessage: String?

    private static let knownToolIds = ["write_action_item", "web_search_and_fetch", "headless_browser_scout", "send_notification_email", "github_agent", "fetch_bee_ai_context", "incoming_email_trigger", "multi_step_search", "read_research_snapshot", "write_research_snapshot"]
    private let backendSync = IOSBackendSyncService()

    var body: some View {
        NavigationStack {
            List {
                ForEach(missions, id: \.id) { mission in
                    NavigationLink {
                        MissionEditView(
                            mission: mission,
                            toolIds: Self.knownToolIds,
                            familyMembers: familyMembers,
                            defaultOwnerProfileId: profileStore.currentProfileId,
                            onSave: { name, prompt, schedule, tools, ownerProfileId in
                                IOSRuntimeLog.log("[MissionListView] Saving existing mission '\(name)' schedule=\(schedule) tools=\(tools.joined(separator: ",")) owner=\(ownerProfileId?.uuidString ?? "none")")
                                try await backendSync.saveMission(
                                    existingMission: mission,
                                    name: name,
                                    prompt: prompt,
                                    schedule: schedule,
                                    tools: tools,
                                    ownerProfileId: ownerProfileId,
                                    modelContext: modelContext
                                )
                                IOSRuntimeLog.log("[MissionListView] Saved existing mission id=\(mission.id.uuidString)")
                            },
                            onRunNow: {
                                try await backendSync.runMissionNow(mission)
                            }
                        )
                    } label: {
                        MissionRow(
                            mission: mission,
                            ownerName: mission.ownerProfileId.flatMap { id in
                                familyMembers.first(where: { $0.id == id })?.displayName
                            }
                        )
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            requestRunNow(mission)
                        } label: {
                            Label("Run Now", systemImage: "play.fill")
                        }
                        .tint(.blue)
                    }
                }
                .onDelete(perform: deleteMissions)
            }
            .navigationTitle("Missions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") { showAddMission = true }
                }
            }
            .familyProfileToolbar()
            .sheet(isPresented: $showAddMission) {
                MissionEditView(
                    mission: nil,
                    toolIds: Self.knownToolIds,
                    familyMembers: familyMembers,
                    defaultOwnerProfileId: profileStore.currentProfileId
                ) { name, prompt, schedule, tools, ownerProfileId in
                    IOSRuntimeLog.log("[MissionListView] Creating mission '\(name)' schedule=\(schedule) tools=\(tools.joined(separator: ",")) owner=\(ownerProfileId?.uuidString ?? "none")")
                    try await backendSync.saveMission(
                        existingMission: nil,
                        name: name,
                        prompt: prompt,
                        schedule: schedule,
                        tools: tools,
                        ownerProfileId: ownerProfileId,
                        modelContext: modelContext
                    )
                    let refreshedMission = missions.first {
                        $0.missionName == name && $0.triggerSchedule == schedule
                    }
                    IOSRuntimeLog.log("[MissionListView] Created mission id=\(refreshedMission?.id.uuidString ?? "unknown")")
                    showAddMission = false
                }
            }
        }
        .alert("Delete Mission Failed", isPresented: Binding(
            get: { deletionErrorMessage != nil },
            set: { if !$0 { deletionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { deletionErrorMessage = nil }
        } message: {
            Text(deletionErrorMessage ?? "The mission could not be deleted.")
        }
        .alert("Run Now Failed", isPresented: Binding(
            get: { runNowErrorMessage != nil },
            set: { if !$0 { runNowErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { runNowErrorMessage = nil }
        } message: {
            Text(runNowErrorMessage ?? "Could not request a run.")
        }
        .alert("Run Requested", isPresented: Binding(
            get: { runNowConfirmationMessage != nil },
            set: { if !$0 { runNowConfirmationMessage = nil } }
        )) {
            Button("OK", role: .cancel) { runNowConfirmationMessage = nil }
        } message: {
            Text(runNowConfirmationMessage ?? "The mission will run on the next scheduler tick.")
        }
        .onAppear {
            logMissionSnapshot(reason: "Appeared")
        }
        .task {
            await backendSync.syncMissions(modelContext: modelContext)
        }
        .onChange(of: missionVisibilitySignature) { _, _ in
            logMissionSnapshot(reason: "Mission list changed")
        }
    }

    private var missionVisibilitySignature: [String] {
        missions.map {
            "\($0.id.uuidString)|\($0.updatedAt.timeIntervalSince1970)|\($0.isEnabled)|\($0.triggerSchedule)"
        }
    }

    private func logMissionSnapshot(reason: String) {
        let missionList = missions
            .map { mission in
                "\(mission.missionName) [\(mission.triggerSchedule)] enabled=\(mission.isEnabled) owner=\(mission.ownerProfileId?.uuidString ?? "none")"
            }
            .joined(separator: "; ")
        if missionList.isEmpty {
            IOSRuntimeLog.log("[MissionListView] \(reason): 0 mission(s) visible on iOS.")
        } else {
            IOSRuntimeLog.log("[MissionListView] \(reason): \(missions.count) mission(s) visible on iOS. Visible: \(missionList)")
        }
    }

    private func requestRunNow(_ mission: MissionDefinition) {
        IOSRuntimeLog.log("[MissionListView] Run Now tapped for '\(mission.missionName)' id=\(mission.id.uuidString)")
        Task { @MainActor in
            do {
                try await backendSync.runMissionNow(mission)
                runNowConfirmationMessage = "'\(mission.missionName)' queued. It will run on the next scheduler tick (within ~30 seconds)."
            } catch {
                runNowErrorMessage = error.localizedDescription
                IOSRuntimeLog.log("[MissionListView] Run Now failed for '\(mission.missionName)': \(error)")
            }
        }
    }

    private func deleteMissions(at offsets: IndexSet) {
        let missionsToDelete = offsets.map { missions[$0] }
        guard !missionsToDelete.isEmpty else { return }

        let deletedSummary = missionsToDelete
            .map { "\($0.missionName) (\($0.id.uuidString))" }
            .joined(separator: ", ")
        IOSRuntimeLog.log("[MissionListView] Deleting \(missionsToDelete.count) mission(s): \(deletedSummary)")

        Task { @MainActor in
            do {
                try await backendSync.deleteMissions(missionsToDelete, modelContext: modelContext)
                IOSRuntimeLog.log("[MissionListView] Deleted \(missionsToDelete.count) mission(s).")
            } catch {
                deletionErrorMessage = error.localizedDescription
                IOSRuntimeLog.log("[MissionListView] Mission deletion failed: \(error)")
            }
        }
    }
}

struct MissionRow: View {
    let mission: MissionDefinition
    let ownerName: String?

    private var isPending: Bool {
        guard let requested = mission.runRequestedAt else { return false }
        guard let lastRun = mission.lastRunAt else { return true }
        return requested > lastRun
    }

    var body: some View {
        HStack(alignment: .center) {
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
            Spacer()
            if isPending {
                ProgressView()
                    .controlSize(.small)
                    .tint(.blue)
            }
        }
    }
}

struct MissionEditView: View {
    let mission: MissionDefinition?
    let toolIds: [String]
    let familyMembers: [FamilyMember]
    let defaultOwnerProfileId: UUID?
    let onSave: @MainActor (String, String, String, [String], UUID?) async throws -> Void
    var onRunNow: (@MainActor () async throws -> Void)? = nil

    private enum ScheduleKind: String, CaseIterable {
        case daily
        case weekly
        case interval
        case webhook

        var pickerLabel: String {
            switch self {
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .interval: return "Interval"
            case .webhook: return "Webhook"
            }
        }
    }

    /// Lowercase weekday names matching `MissionScheduler` / server expectations.
    private static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    private static func displayLabel(forToolId id: String) -> String {
        switch id {
        case "write_action_item": return "Write Action Item"
        case "web_search_and_fetch": return "Web Search & Fetch"
        case "headless_browser_scout": return "Headless Browser Scout"
        case "send_notification_email": return "Send Notification Email"
        case "github_agent": return "GitHub Agent"
        case "fetch_bee_ai_context": return "Fetch Bee Context"
        case "incoming_email_trigger": return "Incoming Email Trigger"
        case "multi_step_search": return "Multi-Step Search"
        case "read_research_snapshot": return "Read Research Snapshot"
        case "write_research_snapshot": return "Write Research Snapshot"
        default:
            return id.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    @State private var name: String = ""
    @State private var systemPrompt: String = ""
    @State private var scheduleKind: ScheduleKind = .daily
    /// Time-of-day for `daily|HH:mm` (only hour and minute are used).
    @State private var dailyRunTime: Date = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
    /// Any calendar date on the chosen weekday for `weekly|weekday` (only weekday is encoded).
    @State private var weeklyPickDate: Date = Date()
    @State private var intervalHours: Int = 6
    @State private var selectedToolIds: Set<String> = []
    @State private var ownerProfileId: UUID?
    @State private var validationMessage: String?
    @State private var isSaving = false
    @State private var isRunningNow = false
    @State private var runNowMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var runtimeToolingNote: String {
        if selectedToolIds.contains("write_action_item") {
            return "Selected tools are injected automatically at runtime. With Write Action Item enabled, the runner will require at least one visible action using calendar.create, mail.reply, reminder.add, or url.open."
        }
        return "Selected tools are injected automatically at runtime, so your prompt can stay focused on the job to be done."
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPrompt: String {
        systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedSchedule: String {
        switch scheduleKind {
        case .daily:
            let cal = Calendar.current
            let h = cal.component(.hour, from: dailyRunTime)
            let m = cal.component(.minute, from: dailyRunTime)
            return String(format: "daily|%02d:%02d", h, m)
        case .weekly:
            let cal = Calendar.current
            let weekday = cal.component(.weekday, from: weeklyPickDate)
            let name = Self.weekdayNames[weekday - 1]
            return "weekly|\(name)"
        case .interval:
            return "interval|\(intervalHours)h"
        case .webhook:
            return "webhook"
        }
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
        if normalizedSchedule.range(of: #"^interval\|([1-9]|[1-9][0-9]{1,2})h$"#, options: .regularExpression) != nil {
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
                    TextField(
                        "System prompt",
                        text: $systemPrompt,
                        prompt: Text("Describe what this mission should do on each run (goals, constraints, and desired outcome)."),
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                    Text(runtimeToolingNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Schedule") {
                    Picker("Schedule type", selection: $scheduleKind) {
                        ForEach(ScheduleKind.allCases, id: \.self) { kind in
                            Text(kind.pickerLabel).tag(kind)
                        }
                    }
                    switch scheduleKind {
                    case .daily:
                        DatePicker("Run at", selection: $dailyRunTime, displayedComponents: .hourAndMinute)
                        Text("Runs every day at this time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .weekly:
                        DatePicker("On weekday", selection: $weeklyPickDate, displayedComponents: .date)
                        Text("Runs once each week on the weekday of the date you pick.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .interval:
                        Stepper(value: $intervalHours, in: 1...999) {
                            Text("Every \(intervalHours) hour\(intervalHours == 1 ? "" : "s")")
                        }
                        Text("Encoded as interval|\(intervalHours)h.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .webhook:
                        Text("Runs only when triggered externally (not on a timer).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                        Toggle(Self.displayLabel(forToolId: id), isOn: Binding(
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
                if let onRunNow, mission != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isRunningNow = true
                            Task { @MainActor in
                                do {
                                    try await onRunNow()
                                    runNowMessage = "Run requested. The Mac will pick it up on the next scheduler tick."
                                } catch {
                                    runNowMessage = "Run failed: \(error.localizedDescription)"
                                }
                                isRunningNow = false
                            }
                        } label: {
                            if isRunningNow {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Run Now", systemImage: "play.fill")
                            }
                        }
                        .disabled(isRunningNow)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        guard isFormValid else {
                            validationMessage = validationError()
                            IOSRuntimeLog.log("[MissionEditView] Validation failed for '\(trimmedName)': \(validationMessage ?? "Unknown validation error.")")
                            return
                        }
                        let sortedToolIds = Array(selectedToolIds).sorted()
                        IOSRuntimeLog.log("[MissionEditView] Save tapped for '\(trimmedName)' schedule=\(normalizedSchedule) tools=\(sortedToolIds.joined(separator: ",")) owner=\(ownerProfileId?.uuidString ?? "none")")
                        isSaving = true
                        Task { @MainActor in
                            do {
                                try await onSave(trimmedName, trimmedPrompt, normalizedSchedule, sortedToolIds, ownerProfileId)
                                validationMessage = nil
                                dismiss()
                            } catch {
                                validationMessage = "Save failed: \(error.localizedDescription)"
                                IOSRuntimeLog.log("[MissionEditView] Save failed for '\(trimmedName)': \(error)")
                            }
                            isSaving = false
                        }
                    }
                    .disabled(!isFormValid || isSaving)
                }
            }
            .onAppear {
                if let m = mission {
                    name = m.missionName
                    systemPrompt = m.systemPrompt
                    applyScheduleFromString(m.triggerSchedule)
                    selectedToolIds = Set(m.allowedMCPTools)
                    ownerProfileId = m.ownerProfileId
                } else {
                    ownerProfileId = defaultOwnerProfileId
                }
            }
            .onChange(of: name) { _, _ in validationMessage = nil }
            .onChange(of: systemPrompt) { _, _ in validationMessage = nil }
            .onChange(of: scheduleKind) { _, _ in validationMessage = nil }
            .onChange(of: dailyRunTime) { _, _ in validationMessage = nil }
            .onChange(of: weeklyPickDate) { _, _ in validationMessage = nil }
            .onChange(of: intervalHours) { _, _ in validationMessage = nil }
            .onChange(of: selectedToolIds) { _, _ in validationMessage = nil }
            .alert("Run Now", isPresented: Binding(
                get: { runNowMessage != nil },
                set: { if !$0 { runNowMessage = nil } }
            )) {
                Button("OK", role: .cancel) { runNowMessage = nil }
            } message: {
                Text(runNowMessage ?? "")
            }
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
            return "Schedule is invalid."
        }
        return "Mission is invalid."
    }

    private func applyScheduleFromString(_ raw: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s == "webhook" {
            scheduleKind = .webhook
            return
        }
        let parts = s.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            scheduleKind = .daily
            return
        }
        switch parts[0] {
        case "daily":
            scheduleKind = .daily
            let hm = parts[1].split(separator: ":")
            if let h = Int(hm[0]), (0..<24).contains(h) {
                let minute = hm.count > 1 ? (Int(hm[1]) ?? 0) : 0
                if (0..<60).contains(minute), let d = Calendar.current.date(from: DateComponents(hour: h, minute: minute)) {
                    dailyRunTime = d
                }
            }
        case "weekly":
            scheduleKind = .weekly
            let day = parts[1]
            if let idx = Self.weekdayNames.firstIndex(of: day) {
                weeklyPickDate = Self.referenceDate(forWeekdayIndex: idx, calendar: .current)
            }
        case "interval":
            scheduleKind = .interval
            let v = parts[1].lowercased()
            if v.hasSuffix("h"), let h = Int(v.dropLast()), (1...999).contains(h) {
                intervalHours = h
            }
        default:
            scheduleKind = .daily
        }
    }

    /// A calendar date whose weekday matches `weekdayNames[index]` (0 = Sunday).
    private static func referenceDate(forWeekdayIndex index: Int, calendar: Calendar) -> Date {
        let targetWeekday = index + 1
        var date = Date()
        for _ in 0..<14 {
            if calendar.component(.weekday, from: date) == targetWeekday {
                return calendar.startOfDay(for: date)
            }
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return Date()
    }
}
