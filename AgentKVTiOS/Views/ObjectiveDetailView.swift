import SwiftUI

struct ObjectiveDetailView: View {
    let objective: IOSBackendObjective

    @Environment(ObjectivesStore.self) private var store
    @State private var displayedObjective: IOSBackendObjective
    @State private var detail: IOSBackendObjectiveDetail?
    @State private var pollTask: Task<Void, Never>?
    @State private var isLoading = false
    @State private var isStartingWork = false
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var showEditPromptSheet = false
    @State private var showDeleteConfirmation = false
    @State private var showRerunAllConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var lastLoadedAt: Date?

    @Environment(\.dismiss) private var dismiss

    init(objective: IOSBackendObjective) {
        self.objective = objective
        _displayedObjective = State(initialValue: objective)
    }

    private var tasks: [IOSBackendTask] {
        detail?.tasks ?? []
    }

    private var snapshots: [IOSBackendResearchSnapshot] {
        detail?.researchSnapshots ?? []
    }

    private var agentLogs: [IOSBackendAgentLog] {
        detail?.agentLogs ?? []
    }

    private var taskCounts: ObjectiveTaskCounts {
        ObjectiveTaskCounts(tasks: tasks)
    }

    private var runNowLabel: String {
        switch displayedObjective.status {
        case "pending":
            return "Start work now"
        case "active":
            if tasks.isEmpty { return "Plan tasks now" }
            if taskCounts.pending > 0 { return "Run now (queue pending)" }
            if taskCounts.failed > 0 && taskCounts.inProgress == 0 { return "Retry failed tasks" }
            if taskCounts.completed > 0 && taskCounts.pending == 0 && taskCounts.inProgress == 0 {
                return "Run now"
            }
            return "Run now"
        default:
            return "Run now"
        }
    }

    private var actionsFooter: String {
        switch displayedObjective.status {
        case "active":
            return """
            Run now queues pending or failed tasks. Use “Reset stuck tasks & run” if work is stuck in progress. \
            “Rerun all tasks” sets every task back to pending and dispatches the Mac agent again.
            """
        default:
            return "Activates this objective and starts planning or task execution."
        }
    }

    private var shouldAutoRefresh: Bool {
        guard displayedObjective.status == "active" else { return false }
        return detail == nil ||
            tasks.isEmpty ||
            taskCounts.pending > 0 ||
            taskCounts.inProgress > 0
    }

    private var activitySummary: ObjectiveActivitySummary {
        if isStartingWork {
            return ObjectiveActivitySummary(
                title: "Starting work",
                message: "Telling the server to activate this objective and dispatch any available tasks now.",
                systemImage: "bolt.badge.clock",
                tint: .blue,
                showsProgress: true
            )
        }

        switch displayedObjective.status {
        case "pending":
            return ObjectiveActivitySummary(
                title: "Saved but not started",
                message: "No planner or Mac-agent work has been dispatched yet. Use Start work now in Actions below.",
                systemImage: "pause.circle.fill",
                tint: .orange
            )
        case "active":
            if taskCounts.inProgress > 0 {
                return ObjectiveActivitySummary(
                    title: "Agent is working",
                    message: "\(taskCounts.inProgress) task(s) are currently in progress. This screen refreshes automatically while work is active.",
                    systemImage: "bolt.circle.fill",
                    tint: .blue,
                    showsProgress: true
                )
            }
            if taskCounts.pending > 0 {
                return ObjectiveActivitySummary(
                    title: "Tasks are queued",
                    message: "\(taskCounts.pending) task(s) are waiting for the Mac agent. Tap Start Pending Tasks if you want to nudge dispatch right now.",
                    systemImage: "clock.fill",
                    tint: .orange
                )
            }
            if tasks.isEmpty {
                return ObjectiveActivitySummary(
                    title: "Planning tasks",
                    message: "The server should break this prompt into concrete research tasks first. If nothing appears, tap Plan Tasks Now.",
                    systemImage: "sparkles",
                    tint: .blue,
                    showsProgress: shouldAutoRefresh
                )
            }
            if taskCounts.failed > 0 {
                return ObjectiveActivitySummary(
                    title: "Some tasks failed",
                    message: "\(taskCounts.failed) task(s) failed. Tap Retry Failed Tasks to requeue them for the agent.",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .red
                )
            }
            if !snapshots.isEmpty || taskCounts.completed > 0 {
                return ObjectiveActivitySummary(
                    title: "Research available",
                    message: "\(taskCounts.completed) task(s) completed and \(snapshots.count) snapshot(s) are available below.",
                    systemImage: "checkmark.circle.fill",
                    tint: .green
                )
            }
            return ObjectiveActivitySummary(
                title: "Active",
                message: "This objective is active, but there is no task movement yet.",
                systemImage: "circle.fill",
                tint: .blue
            )
        case "completed":
            return ObjectiveActivitySummary(
                title: "Marked completed",
                message: "The objective itself is marked completed. Existing tasks and research remain visible below.",
                systemImage: "checkmark.seal.fill",
                tint: .green
            )
        case "archived":
            return ObjectiveActivitySummary(
                title: "Archived",
                message: "Archived objectives are preserved for reference and are not expected to dispatch new work.",
                systemImage: "archivebox.fill",
                tint: .gray
            )
        default:
            return ObjectiveActivitySummary(
                title: "Waiting",
                message: "No agent activity detected yet.",
                systemImage: "hourglass",
                tint: .secondary
            )
        }
    }

    var body: some View {
        List {
            Section("Activity") {
                if !snapshots.isEmpty {
                    NavigationLink {
                        GenerativeResultsView(
                            objectiveId: displayedObjective.id,
                            objectiveGoal: displayedObjective.goal,
                            snapshots: snapshots
                        )
                    } label: {
                        ObjectiveActivityCard(
                            summary: activitySummary,
                            taskCounts: taskCounts,
                            snapshotCount: snapshots.count,
                            logCount: agentLogs.count,
                            lastLoadedAt: lastLoadedAt,
                            showsDisclosure: true
                        )
                    }
                } else {
                    ObjectiveActivityCard(
                        summary: activitySummary,
                        taskCounts: taskCounts,
                        snapshotCount: snapshots.count,
                        logCount: agentLogs.count,
                        lastLoadedAt: lastLoadedAt
                    )
                }
            }

            if displayedObjective.status == "pending" || displayedObjective.status == "active" {
                Section {
                    Button {
                        Task { await runObjectiveNow() }
                    } label: {
                        Label(runNowLabel, systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isStartingWork || isDeleting)

                    if displayedObjective.status == "active", taskCounts.inProgress > 0 {
                        Button {
                            Task { await resetStuckTasksAndRun() }
                        } label: {
                            Label("Reset stuck tasks & run", systemImage: "arrow.uturn.backward.circle")
                        }
                        .disabled(isStartingWork || isDeleting)
                    }

                    if displayedObjective.status == "active" {
                        Button(role: .destructive) {
                            showRerunAllConfirmation = true
                        } label: {
                            Label("Rerun all tasks", systemImage: "arrow.clockwise.circle")
                        }
                        .disabled(isStartingWork || isDeleting)
                    }
                } header: {
                    Text("Actions")
                } footer: {
                    Text(actionsFooter)
                }
            }

            Section {
                Text(displayedObjective.goal)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Edit prompt") {
                    showEditPromptSheet = true
                }
            } header: {
                Text("Prompt")
            }

            // Tasks
            Section {
                if !tasks.isEmpty {
                    ForEach(tasks) { task in
                        TaskRow(task: task)
                    }
                } else if !isLoading {
                    Text("No tasks yet.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            } header: {
                Text("Tasks")
            }

            // Research Snapshots
            Section {
                if !snapshots.isEmpty {
                    ForEach(snapshots) { snapshot in
                        SnapshotRow(snapshot: snapshot)
                    }
                } else if !isLoading {
                    Text("No research data yet.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            } header: {
                Text("Research")
            }

            Section("Recent Agent Logs") {
                if !agentLogs.isEmpty {
                    ForEach(Array(agentLogs.prefix(8)), id: \.id) { log in
                        ObjectiveAgentLogRow(log: log)
                    }
                } else if !isLoading {
                    Text("No objective-scoped agent logs yet.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle(displayedObjective.goal)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Delete", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
        }
        .confirmationDialog(
            "Delete objective?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteObjective() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tasks and research tied to this objective will be removed.")
        }
        .refreshable { await loadDetail(showSpinner: false) }
        .overlay {
            if isLoading || isDeleting || isStartingWork {
                ProgressView()
            }
        }
        .alert("Could Not Load Detail", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An error occurred.")
        }
        .confirmationDialog(
            "Rerun all tasks?",
            isPresented: $showRerunAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Rerun all tasks", role: .destructive) {
                Task { await rerunAllTasks() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every task resets to pending and the Mac agent is asked to run them again. Existing research snapshots may still be listed until new results arrive.")
        }
        .alert("Action failed", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "An error occurred.")
        }
        .alert("Could Not Delete Objective", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "An error occurred.")
        }
        .task { await loadDetail() }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
        .sheet(isPresented: $showEditPromptSheet) {
            EditObjectivePromptSheet(
                objective: displayedObjective,
                onSaved: { updated in
                    displayedObjective = updated
                    showEditPromptSheet = false
                    Task { await loadDetail(showSpinner: false) }
                }
            )
        }
    }

    @MainActor
    private func loadDetail(showSpinner: Bool = true) async {
        if showSpinner {
            isLoading = true
            errorMessage = nil
        }
        defer {
            if showSpinner {
                isLoading = false
            }
        }

        do {
            detail = try await store.fetchDetail(for: displayedObjective.id)
            if let o = detail?.objective {
                displayedObjective = o
            }
            lastLoadedAt = Date()
            reconcilePolling()
        } catch {
            if showSpinner {
                errorMessage = error.localizedDescription
            } else {
                IOSRuntimeLog.log("[ObjectiveDetailView] Auto-refresh failed: \(error)")
            }
        }
    }

    @MainActor
    private func deleteObjective() async {
        deleteError = nil
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await store.deleteObjective(id: displayedObjective.id)
            dismiss()
        } catch {
            deleteError = error.localizedDescription
        }
    }

    @MainActor
    private func runObjectiveNow() async {
        actionError = nil
        isStartingWork = true
        defer { isStartingWork = false }

        do {
            displayedObjective = try await store.runObjectiveNow(id: displayedObjective.id)
            await loadDetail(showSpinner: false)
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func resetStuckTasksAndRun() async {
        actionError = nil
        isStartingWork = true
        defer { isStartingWork = false }

        do {
            displayedObjective = try await store.resetStuckTasksAndRun(id: displayedObjective.id)
            await loadDetail(showSpinner: false)
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func rerunAllTasks() async {
        actionError = nil
        isStartingWork = true
        defer { isStartingWork = false }

        do {
            displayedObjective = try await store.rerunObjective(id: displayedObjective.id)
            await loadDetail(showSpinner: false)
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func reconcilePolling() {
        guard shouldAutoRefresh else {
            pollTask?.cancel()
            pollTask = nil
            return
        }
        guard pollTask == nil else { return }

        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await loadDetail(showSpinner: false)
            }
        }
    }
}

private struct ObjectiveTaskCounts {
    let pending: Int
    let inProgress: Int
    let completed: Int
    let failed: Int

    init(tasks: [IOSBackendTask]) {
        self.pending = tasks.filter { $0.status == "pending" }.count
        self.inProgress = tasks.filter { $0.status == "in_progress" }.count
        self.completed = tasks.filter { $0.status == "completed" }.count
        self.failed = tasks.filter { $0.status == "failed" }.count
    }

    var hasAnyTasks: Bool {
        pending + inProgress + completed + failed > 0
    }
}

private struct ObjectiveActivitySummary {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    var showsProgress = false
}

private struct ObjectiveActivityCard: View {
    let summary: ObjectiveActivitySummary
    let taskCounts: ObjectiveTaskCounts
    let snapshotCount: Int
    let logCount: Int
    let lastLoadedAt: Date?
    var showsDisclosure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summary.systemImage)
                    .font(.title3)
                    .foregroundStyle(summary.tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title)
                        .font(.headline)
                    Text(summary.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if summary.showsProgress {
                    ProgressView()
                        .tint(summary.tint)
                }

                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 8) {
                if taskCounts.hasAnyTasks {
                    ObjectiveMetricChip(label: "\(taskCounts.pending) pending", tint: .orange)
                    ObjectiveMetricChip(label: "\(taskCounts.inProgress) active", tint: .blue)
                    ObjectiveMetricChip(label: "\(taskCounts.completed) done", tint: .green)
                    if taskCounts.failed > 0 {
                        ObjectiveMetricChip(label: "\(taskCounts.failed) failed", tint: .red)
                    }
                }
                ObjectiveMetricChip(label: "\(snapshotCount) snapshots", tint: .secondary)
                ObjectiveMetricChip(label: "\(logCount) logs", tint: .secondary)
            }

            if let lastLoadedAt {
                Text("Last checked \(lastLoadedAt, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ObjectiveResearchDetailView: View {
    let objectiveGoal: String
    let snapshots: [IOSBackendResearchSnapshot]

    var body: some View {
        List {
            Section("Research Snapshots") {
                if snapshots.isEmpty {
                    Text("No research data yet.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(snapshots) { snapshot in
                        SnapshotRow(snapshot: snapshot)
                    }
                }
            }
        }
        .navigationTitle("Research")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ObjectiveMetricChip: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct ObjectiveAgentLogRow: View {
    let log: IOSBackendAgentLog

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(log.metadataJson["worker_label"]?.stringValue ?? log.phase)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(log.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(log.phase.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(log.content)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Edit prompt

private struct EditObjectivePromptSheet: View {
    let objective: IOSBackendObjective
    var onSaved: (IOSBackendObjective) -> Void

    @Environment(ObjectivesStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var goal: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(objective: IOSBackendObjective, onSaved: @escaping (IOSBackendObjective) -> Void) {
        self.objective = objective
        self.onSaved = onSaved
        _goal = State(initialValue: objective.goal)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    TextField("Goal", text: $goal, axis: .vertical)
                        .lineLimit(4...10)
                }
            }
            .navigationTitle("Edit Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .overlay {
                if isSaving { ProgressView() }
            }
            .alert("Could Not Save Prompt", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "An error occurred.")
            }
        }
    }

    @MainActor
    private func save() async {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let updated = try await store.updateObjective(
                id: objective.id,
                goal: trimmed,
                status: objective.status,
                priority: objective.priority
            )
            onSaved(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Task row

struct TaskRow: View {
    let task: IOSBackendTask

    private var statusColor: Color {
        switch task.status {
        case "in_progress": return .blue
        case "completed":   return .green
        case "failed":      return .red
        default:            return .orange   // pending
        }
    }

    private var statusLabel: String {
        task.status.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.description)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.85))
                    .clipShape(Capsule())
                if let summary = task.resultSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Research snapshot row

struct SnapshotRow: View {
    let snapshot: IOSBackendResearchSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.key)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(snapshot.value)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let delta = snapshot.deltaNote {
                Label(delta, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(snapshot.checkedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
