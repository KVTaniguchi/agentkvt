import SwiftUI

struct ObjectiveDetailView: View {
    let objective: IOSBackendObjective

    @Environment(ObjectivesStore.self) private var store
    @State private var displayedObjective: IOSBackendObjective
    @State private var detail: IOSBackendObjectiveDetail?
    @State private var pollTask: Task<Void, Never>?
    @State private var isLoading = false
    @State private var isStartingWork = false
    @State private var actionInProgress: String?
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var showEditPromptSheet = false
    @State private var showDeleteConfirmation = false
    @State private var showRerunAllConfirmation = false
    @State private var isDeleting = false
    @State private var isSubmittingFeedback = false
    @State private var deleteError: String?
    @State private var lastLoadedAt: Date?
    @State private var feedbackDraft = ""
    @State private var selectedFeedbackKind = ObjectiveFeedbackKindOption.followUp.rawValue
    @State private var selectedFeedbackTargetID = ObjectiveFeedbackTarget.objectiveID
    @State private var highlightedFeedbackID: UUID?
    @State private var editingFeedbackContext: ObjectiveFeedbackComposerContext?
    @State private var feedbackPlanActionInProgressID: UUID?
    @State private var guidance: ObjectiveGuidance?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

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

    private var objectiveFeedbacks: [IOSBackendObjectiveFeedback] {
        detail?.objectiveFeedbacks ?? []
    }

    private var taskCounts: ObjectiveTaskCounts {
        ObjectiveTaskCounts(tasks: tasks)
    }

    private var needsPlanReview: Bool {
        taskCounts.initialProposed > 0
    }

    private var hasFollowUpPlanReview: Bool {
        objectiveFeedbacks.contains { $0.status == "review_required" }
    }

    private var promotedReviewFeedback: IOSBackendObjectiveFeedback? {
        objectiveFeedbacks
            .filter { $0.status == "review_required" }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    private var followUpLoopFeedbacks: [IOSBackendObjectiveFeedback] {
        objectiveFeedbacks.sorted { $0.createdAt > $1.createdAt }
    }

    private var followUpHistoryFeedbacks: [IOSBackendObjectiveFeedback] {
        followUpLoopFeedbacks.filter { $0.id != promotedReviewFeedback?.id }
    }

    private var hasApprovedPlanWaitingToStart: Bool {
        displayedObjective.status == "pending" && taskCounts.pending > 0
    }

    private var onlineAgentRegistrationsCount: Int {
        detail?.onlineAgentRegistrationsCount ?? 0
    }

    private var guidanceLastFinding: String? { guidance?.lastFinding }
    private var guidanceIdleReason: String? { guidance?.idleReason }
    private var isIdleResumeState: Bool { guidance?.actionKind == .resume }
    private var showGuidanceButton: Bool {
        guard let g = guidance else { return false }
        return !g.buttonLabel.isEmpty && g.actionKind != .allDone && g.actionKind != .monitor
    }

    /// Inline "Next step" section — avoids `safeAreaInset` floating over short `List` content (Actions).
    private var shouldShowOrchestratorSection: Bool {
        guard showGuidanceButton, let g = guidance else { return false }
        if promotedReviewFeedback != nil { return false }
        if g.actionKind == .approvePlan && needsPlanReview { return false }
        if g.actionKind == .resume { return false }
        return true
    }

    private var trimmedFeedbackDraft: String {
        feedbackDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowFeedbackLoop: Bool {
        !objectiveFeedbacks.isEmpty || !snapshots.isEmpty || taskCounts.completed > 0
    }

    private var canSubmitFeedback: Bool {
        guard promotedReviewFeedback == nil else { return false }
        return shouldShowFeedbackLoop && (displayedObjective.status == "pending" || displayedObjective.status == "active")
    }

    private var feedbackTargets: [ObjectiveFeedbackTarget] {
        var targets = [ObjectiveFeedbackTarget(
            id: ObjectiveFeedbackTarget.objectiveID,
            label: "Entire objective",
            preview: ObjectiveFeedbackPresentation.previewText(displayedObjective.goal)
        )]
        targets.append(contentsOf: snapshots.prefix(6).map {
            ObjectiveFeedbackTarget(
                id: "snapshot-\($0.id.uuidString)",
                label: ObjectiveFeedbackPresentation.targetLabel(for: $0),
                preview: ObjectiveFeedbackPresentation.previewText($0.value),
                researchSnapshotId: $0.id
            )
        })
        targets.append(contentsOf: tasks.prefix(8).map {
            ObjectiveFeedbackTarget(
                id: "task-\($0.id.uuidString)",
                label: "Task: \($0.description)",
                preview: ObjectiveFeedbackPresentation.previewText($0.description),
                taskId: $0.id
            )
        })
        return targets
    }

    private var selectedFeedbackTarget: ObjectiveFeedbackTarget {
        feedbackTargets.first(where: { $0.id == selectedFeedbackTargetID })
            ?? feedbackTargets.first
            ?? .init(id: ObjectiveFeedbackTarget.objectiveID, label: "Entire objective", preview: nil)
    }

    /// System `borderedProminent` + default tint often yields a pale blue fill in dark mode; white labels are hard to read.
    private var runNowProminentTint: Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.38, blue: 0.82)
            : Color(red: 0.0, green: 0.45, blue: 0.94)
    }

    private var runNowLabel: String {
        switch displayedObjective.status {
        case "pending":
            if hasApprovedPlanWaitingToStart { return "Start approved plan" }
            return "Generate plan"
        case "active":
            if tasks.isEmpty { return "Generate plan" }
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

    @ViewBuilder
    private var agentLogsSectionContent: some View {
        if !agentLogs.isEmpty {
            ForEach(Array(agentLogs.prefix(8)), id: \.id) { (log: IOSBackendAgentLog) in
                ObjectiveAgentLogRow(log: log)
            }
        } else if !isLoading {
            Text("No objective-scoped agent logs yet.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private var activitySectionContent: some View {
        if let promotedReviewFeedback {
            VStack(alignment: .leading, spacing: 12) {
                ObjectiveActivityCard(
                    summary: activitySummary,
                    taskCounts: taskCounts,
                    onlineAgentRegistrationsCount: onlineAgentRegistrationsCount,
                    snapshotCount: snapshots.count,
                    logCount: agentLogs.count,
                    lastLoadedAt: lastLoadedAt,
                    lastFinding: nil,
                    showsOperationalMetrics: false,
                    statusPillLabel: "Review required",
                    statusPillTint: .teal
                )

                feedbackCard(for: promotedReviewFeedback, isPromoted: true)
            }
        } else if !snapshots.isEmpty {
            NavigationLink {
                GenerativeResultsView(
                    objectiveId: displayedObjective.id,
                    objectiveGoal: displayedObjective.goal,
                    objectiveStatus: displayedObjective.status,
                    tasks: tasks,
                    snapshots: snapshots,
                    onlineAgentRegistrationsCount: onlineAgentRegistrationsCount,
                    onFeedbackMutated: {
                        Task { await loadDetail(showSpinner: false) }
                    }
                )
            } label: {
                ObjectiveActivityCard(
                    summary: activitySummary,
                    taskCounts: taskCounts,
                    onlineAgentRegistrationsCount: onlineAgentRegistrationsCount,
                    snapshotCount: snapshots.count,
                    logCount: agentLogs.count,
                    lastLoadedAt: lastLoadedAt,
                    lastFinding: guidanceLastFinding,
                    showsDisclosure: true
                )
            }
        } else if isIdleResumeState {
            ObjectiveIdleEmptyState(idleReason: guidanceIdleReason)
        } else {
            ObjectiveActivityCard(
                summary: activitySummary,
                taskCounts: taskCounts,
                onlineAgentRegistrationsCount: onlineAgentRegistrationsCount,
                snapshotCount: snapshots.count,
                logCount: agentLogs.count,
                lastLoadedAt: lastLoadedAt,
                lastFinding: guidanceLastFinding
            )
        }
    }

    @ViewBuilder
    private var lowerSectionsContent: some View {
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
        } footer: {
            if needsPlanReview {
                Text("If you change the prompt, regenerate the plan so the proposed task list matches the updated objective.")
            }
        }

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

        if canSubmitFeedback {
            Section {
                Picker("Intent", selection: $selectedFeedbackKind) {
                    ForEach(ObjectiveFeedbackKindOption.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)

                if feedbackTargets.count > 1 {
                    Picker("Focus", selection: $selectedFeedbackTargetID) {
                        ForEach(feedbackTargets) { target in
                            Text(target.label).tag(target.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                TextField("Tell AgentKVT what to research next...", text: $feedbackDraft, axis: .vertical)
                    .lineLimit(3...6)

                Button {
                    Task { await submitObjectiveFeedback() }
                } label: {
                    HStack {
                        Label("Create Next Pass", systemImage: "arrow.triangle.branch")
                        if isSubmittingFeedback {
                            ProgressView().padding(.leading, 4)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(runNowProminentTint)
                .disabled(trimmedFeedbackDraft.isEmpty || isSubmittingFeedback || isStartingWork || isDeleting)
            } header: {
                Text("Continue Research")
            } footer: {
                Text("Submitting feedback creates the next pass for this objective. Review stays visible below, and active objectives can queue approved work automatically.")
            }
        }

        if !followUpHistoryFeedbacks.isEmpty {
            Section("Follow-up Loop") {
                ForEach(followUpHistoryFeedbacks) { feedback in
                    feedbackCard(for: feedback)
                }
            }
        }
    }

    @ViewBuilder
    private var actionsSectionContent: some View {
        if needsPlanReview {
            Button {
                actionInProgress = "approvePlan"
                Task { await approveObjectivePlan() }
            } label: {
                HStack {
                    Label(
                        displayedObjective.status == "active" ? "Approve plan & start work" : "Approve plan",
                        systemImage: "checkmark.circle.fill"
                    )
                    if actionInProgress == "approvePlan" || isStartingWork && actionInProgress == nil {
                        ProgressView().padding(.leading, 4)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(runNowProminentTint)
            .disabled(isStartingWork || isDeleting)

            Button {
                actionInProgress = "regeneratePlan"
                Task { await regenerateObjectivePlan() }
            } label: {
                HStack {
                    Label("Regenerate plan", systemImage: "arrow.trianglehead.clockwise")
                    if actionInProgress == "regeneratePlan" {
                        ProgressView().padding(.leading, 4)
                    }
                }
            }
            .disabled(isStartingWork || isDeleting)
        } else {
            Button {
                actionInProgress = "runNow"
                Task { await runObjectiveNow() }
            } label: {
                HStack {
                    Label(runNowLabel, systemImage: "play.circle.fill")
                    if actionInProgress == "runNow" {
                        ProgressView().padding(.leading, 4)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(runNowProminentTint)
            .disabled(isStartingWork || isDeleting)

            if displayedObjective.status == "active", taskCounts.inProgress > 0 {
                Button {
                    actionInProgress = "resetTasks"
                    Task { await resetStuckTasksAndRun() }
                } label: {
                    HStack {
                        Label("Reset stuck tasks & run", systemImage: "arrow.uturn.backward.circle")
                        if actionInProgress == "resetTasks" {
                            ProgressView().padding(.leading, 4)
                        }
                    }
                }
                .disabled(isStartingWork || isDeleting)
            }

            if displayedObjective.status == "active" {
                Button(role: .destructive) {
                    showRerunAllConfirmation = true
                } label: {
                    HStack {
                        Label("Rerun all tasks", systemImage: "arrow.clockwise.circle")
                        if actionInProgress == "rerunTasks" {
                            ProgressView().padding(.leading, 4)
                        }
                    }
                }
                .disabled(isStartingWork || isDeleting)
            }
        }
    }

    private func orchestratorSectionFooter(for g: ObjectiveGuidance) -> String {
        switch g.actionKind {
        case .reviewFeedback:
            return "Review and approve or regenerate this follow-up plan before running more tasks."
        case .approvePlan:
            return "Approve or regenerate this task batch when it looks right."
        case .planNextSteps:
            return "Continue with a new research pass when you are ready."
        case .resume, .monitor, .allDone:
            return ""
        }
    }

    private var actionsFooter: String {
        if needsPlanReview {
            return "Approve the proposed tasks to let the Mac agent begin. If the plan misses the mark, edit the prompt and regenerate it first."
        }

        if hasApprovedPlanWaitingToStart {
            return "This objective already has an approved plan. Start work when you're ready, or edit the prompt and regenerate the plan if you want a different breakdown."
        }

        switch displayedObjective.status {
        case "active":
            return """
            Run now queues pending or failed tasks. Use “Reset stuck tasks & run” if work is stuck in progress. \
            “Rerun all tasks” sets every task back to pending and dispatches the Mac agent again.
            """
        default:
            return "Generates a proposed task plan for review. Work begins after you approve the plan."
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
            if hasFollowUpPlanReview {
                return ObjectiveActivitySummary(
                    title: "Next step: Review follow-up",
                    message: "AgentKVT has prepared a next pass based on your feedback. Review it before more work begins.",
                    systemImage: "arrow.triangle.branch",
                    tint: .teal
                )
            }
            if taskCounts.initialProposed > 0 {
                return ObjectiveActivitySummary(
                    title: "Plan ready for review",
                    message: "\(taskCounts.initialProposed) proposed task(s) are ready. Approve the plan when it looks right, or edit the prompt and regenerate it first.",
                    systemImage: "checklist.checked",
                    tint: .teal
                )
            }
            if taskCounts.pending > 0 {
                return ObjectiveActivitySummary(
                    title: "Approved plan ready",
                    message: "\(taskCounts.pending) approved task(s) are ready. Start work when you want the Mac agent to begin.",
                    systemImage: "play.circle.fill",
                    tint: .blue
                )
            }
            return ObjectiveActivitySummary(
                title: "Saved but not started",
                message: "No plan has been generated yet. Use Generate plan in Actions below, then review the proposed tasks before work begins.",
                systemImage: "pause.circle.fill",
                tint: .orange
            )
        case "active":
            if hasFollowUpPlanReview {
                return ObjectiveActivitySummary(
                    title: "Next step: Review follow-up",
                    message: "AgentKVT has prepared a next pass based on your feedback. Review it before more work continues.",
                    systemImage: "arrow.triangle.branch",
                    tint: .teal
                )
            }
            if taskCounts.initialProposed > 0 {
                return ObjectiveActivitySummary(
                    title: "Plan ready for review",
                    message: "\(taskCounts.initialProposed) proposed task(s) are ready. Approve the plan to dispatch work, or edit the prompt and regenerate the task breakdown.",
                    systemImage: "checklist.checked",
                    tint: .teal
                )
            }
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
                let agentHint: String
                if onlineAgentRegistrationsCount == 0 {
                    agentHint = " The API reports no online Mac agent. Keep the Mac runner up, set AGENTKVT_AGENT_WEBHOOK_PUBLIC_URL to an address your API host can reach (Tailscale/LAN/tunnel—not the server’s 127.0.0.1), and ensure Solid Queue workers are running on the server."
                } else {
                    agentHint = ""
                }
                return ObjectiveActivitySummary(
                    title: "Tasks are queued",
                    message: "\(taskCounts.pending) task(s) are waiting for the Mac agent. Tap Run now below to enqueue dispatch on the server.\(agentHint)",
                    systemImage: "clock.fill",
                    tint: .orange
                )
            }
            if tasks.isEmpty {
                return ObjectiveActivitySummary(
                    title: "Planning tasks",
                    message: "The server should break this prompt into concrete research tasks first. If nothing appears after a moment, try Generate plan again.",
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

    private var listView: some View {
        List {
            Section("Activity") {
                activitySectionContent
            }

            if shouldShowOrchestratorSection, let g = guidance {
                Section {
                    Button {
                        handleGuidanceAction(g.actionKind)
                    } label: {
                        Label(g.buttonLabel, systemImage: g.buttonIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(runNowProminentTint)
                    .disabled(isStartingWork || isDeleting || actionInProgress != nil)
                } header: {
                    Text("Next step")
                } footer: {
                    let footerText = orchestratorSectionFooter(for: g)
                    if !footerText.isEmpty {
                        Text(footerText)
                    }
                }
            }

            if (displayedObjective.status == "pending" || displayedObjective.status == "active") && promotedReviewFeedback == nil {
                Section {
                    actionsSectionContent
                } header: {
                    Text("Actions")
                } footer: {
                    Text(actionsFooter)
                }
            }

            lowerSectionsContent

            Section("Recent Agent Logs") {
                agentLogsSectionContent
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
        .refreshable { await loadDetail(showSpinner: false) }
        .overlay {
            if isDeleting {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Deleting...")
                            .foregroundStyle(.secondary)
                            .font(.headline)
                    }
                    .padding(24)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .task { await loadDetail() }
        .onChange(of: displayedObjective) { recomputeGuidance() }
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
        .sheet(item: $editingFeedbackContext) { context in
            ObjectiveFeedbackComposerSheet(
                objectiveId: displayedObjective.id,
                objectiveGoal: displayedObjective.goal,
                objectiveStatus: displayedObjective.status,
                tasks: tasks,
                snapshots: snapshots,
                editingFeedback: context.existingFeedback,
                initialFeedbackKind: context.feedbackKind,
                initialFeedbackTargetID: context.targetID,
                initialFeedbackDraft: context.draft,
                onSubmitted: { result in
                    highlightedFeedbackID = result.objectiveFeedback.id
                    Task {
                        await loadDetail(showSpinner: false)
                        if result.objectiveFeedback.status == "queued" {
                            await refreshDetailBurst()
                        }
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    var body: some View {
        listView
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
            .alert("Could Not Load Detail", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "An error occurred.")
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
            reconcileFeedbackTargetSelection()
            reconcileHighlightedFeedbackSelection()
            lastLoadedAt = Date()
            recomputeGuidance()
            reconcilePolling()
        } catch {
            if showSpinner {
                errorMessage = error.localizedDescription
            } else {
                IOSRuntimeLog.log("[ObjectiveDetailView] Auto-refresh failed: \(error)")
            }
        }
    }

    private func recomputeGuidance() {
        guard let detail else { guidance = nil; return }
        guidance = ObjectiveGuidanceProvider.compute(
            objective: displayedObjective,
            tasks: detail.tasks,
            feedbacks: detail.objectiveFeedbacks,
            snapshots: detail.researchSnapshots
        )
    }

    private func handleGuidanceAction(_ actionKind: ObjectiveGuidance.ActionKind) {
        switch actionKind {
        case .approvePlan:
            actionInProgress = "approvePlan"
            Task { await approveObjectivePlan() }
        case .reviewFeedback:
            if let feedback = objectiveFeedbacks.first(where: { $0.status == "review_required" }) {
                editingFeedbackContext = composerContext(for: feedback)
            }
        case .planNextSteps:
            editingFeedbackContext = ObjectiveFeedbackComposerContext(
                existingFeedback: nil,
                feedbackKind: ObjectiveFeedbackKindOption.followUp.rawValue,
                targetID: ObjectiveFeedbackTarget.objectiveID,
                draft: ""
            )
        case .resume:
            actionInProgress = "runNow"
            Task { await runObjectiveNow() }
        case .allDone, .monitor:
            break
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
        defer {
            isStartingWork = false
            actionInProgress = nil
        }

        do {
            displayedObjective = try await store.runObjectiveNow(id: displayedObjective.id)
            await loadDetail(showSpinner: false)
            await refreshDetailBurst()
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func approveObjectivePlan() async {
        actionError = nil
        isStartingWork = true
        defer {
            isStartingWork = false
            actionInProgress = nil
        }

        do {
            displayedObjective = try await store.approveObjectivePlan(id: displayedObjective.id)
            await loadDetail(showSpinner: false)
            if displayedObjective.status == "active" {
                await refreshDetailBurst()
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func regenerateObjectivePlan() async {
        actionError = nil
        isStartingWork = true
        defer {
            isStartingWork = false
            actionInProgress = nil
        }

        do {
            displayedObjective = try await store.regenerateObjectivePlan(id: displayedObjective.id)
            detail = nil
            await loadDetail(showSpinner: false)
            await refreshDetailBurst()
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func resetStuckTasksAndRun() async {
        actionError = nil
        isStartingWork = true
        defer {
            isStartingWork = false
            actionInProgress = nil
        }

        do {
            displayedObjective = try await store.resetStuckTasksAndRun(id: displayedObjective.id)
            await loadDetail(showSpinner: false)
            await refreshDetailBurst()
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func rerunAllTasks() async {
        actionError = nil
        isStartingWork = true
        actionInProgress = "rerunTasks"
        defer { 
            isStartingWork = false 
            actionInProgress = nil
        }

        do {
            displayedObjective = try await store.rerunObjective(id: displayedObjective.id)
            await loadDetail(showSpinner: false)
            await refreshDetailBurst()
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func submitObjectiveFeedback() async {
        guard !trimmedFeedbackDraft.isEmpty else { return }

        actionError = nil
        isSubmittingFeedback = true
        defer { isSubmittingFeedback = false }

        do {
            let result = try await store.submitObjectiveFeedback(
                id: displayedObjective.id,
                content: trimmedFeedbackDraft,
                feedbackKind: selectedFeedbackKind,
                taskId: selectedFeedbackTarget.taskId,
                researchSnapshotId: selectedFeedbackTarget.researchSnapshotId
            )
            highlightedFeedbackID = result.objectiveFeedback.id
            feedbackDraft = ""
            selectedFeedbackKind = ObjectiveFeedbackKindOption.followUp.rawValue
            selectedFeedbackTargetID = ObjectiveFeedbackTarget.objectiveID
            await loadDetail(showSpinner: false)
            if result.objectiveFeedback.status == "queued" {
                await refreshDetailBurst()
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// After nudging the server, poll quickly so `in_progress` tasks appear without waiting for the 4s loop.
    @MainActor
    private func refreshDetailBurst() async {
        for _ in 0..<24 {
            try? await Task.sleep(for: .milliseconds(900))
            if Task.isCancelled { break }
            await loadDetail(showSpinner: false)
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

    @MainActor
    private func reconcileFeedbackTargetSelection() {
        if !feedbackTargets.contains(where: { $0.id == selectedFeedbackTargetID }) {
            selectedFeedbackTargetID = feedbackTargets.first?.id ?? ObjectiveFeedbackTarget.objectiveID
        }
    }

    @MainActor
    private func reconcileHighlightedFeedbackSelection() {
        guard let highlightedFeedbackID else { return }
        if !objectiveFeedbacks.contains(where: { $0.id == highlightedFeedbackID }) {
            self.highlightedFeedbackID = nil
        }
    }

    private func followUpTasks(for feedback: IOSBackendObjectiveFeedback) -> [IOSBackendTask] {
        tasks.filter { $0.sourceFeedbackId == feedback.id }
    }

    private func feedbackTargetLabel(for feedback: IOSBackendObjectiveFeedback) -> String {
        if let snapshotId = feedback.researchSnapshotId,
           let snapshot = snapshots.first(where: { $0.id == snapshotId }) {
            return ObjectiveFeedbackPresentation.targetLabel(for: snapshot)
        }
        if let taskId = feedback.taskId,
           let task = tasks.first(where: { $0.id == taskId }) {
            return "Task: \(task.description)"
        }
        return "Entire objective"
    }

    private func feedbackTargetPreview(for feedback: IOSBackendObjectiveFeedback) -> String? {
        if let snapshotId = feedback.researchSnapshotId,
           let snapshot = snapshots.first(where: { $0.id == snapshotId }) {
            return ObjectiveFeedbackPresentation.previewText(snapshot.value)
        }
        if let taskId = feedback.taskId,
           let task = tasks.first(where: { $0.id == taskId }) {
            return ObjectiveFeedbackPresentation.previewText(task.description)
        }
        return ObjectiveFeedbackPresentation.previewText(displayedObjective.goal)
    }

    private func composerContext(for feedback: IOSBackendObjectiveFeedback) -> ObjectiveFeedbackComposerContext {
        ObjectiveFeedbackComposerContext(
            existingFeedback: feedback,
            feedbackKind: feedback.feedbackKind,
            targetID: ObjectiveFeedbackTarget.id(taskId: feedback.taskId, researchSnapshotId: feedback.researchSnapshotId),
            draft: feedback.content
        )
    }

    @ViewBuilder
    private func feedbackCard(for feedback: IOSBackendObjectiveFeedback, isPromoted: Bool = false) -> some View {
        let isReviewRequired = feedback.status == "review_required"

        ObjectiveFeedbackPlanCard(
            model: ObjectiveFeedbackCardModel(
                feedback: feedback,
                targetLabel: feedbackTargetLabel(for: feedback),
                targetPreview: feedbackTargetPreview(for: feedback),
                followUpTasks: followUpTasks(for: feedback)
            ),
            objectiveStatus: displayedObjective.status,
            isHighlighted: isPromoted || highlightedFeedbackID == feedback.id,
            isWorking: feedbackPlanActionInProgressID == feedback.id,
            onApprove: isReviewRequired ? {
                Task { await approveObjectiveFeedbackPlan(feedback) }
            } : nil,
            onRegenerate: isReviewRequired ? {
                Task { await regenerateObjectiveFeedbackPlan(feedback) }
            } : nil,
            onEdit: isReviewRequired ? {
                editingFeedbackContext = composerContext(for: feedback)
            } : nil
        )
    }

    @MainActor
    private func approveObjectiveFeedbackPlan(_ feedback: IOSBackendObjectiveFeedback) async {
        actionError = nil
        feedbackPlanActionInProgressID = feedback.id
        defer { feedbackPlanActionInProgressID = nil }

        do {
            let result = try await store.approveObjectiveFeedbackPlan(
                objectiveId: displayedObjective.id,
                feedbackId: feedback.id
            )
            highlightedFeedbackID = result.objectiveFeedback.id
            await loadDetail(showSpinner: false)
            if result.objectiveFeedback.status == "queued" {
                await refreshDetailBurst()
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func regenerateObjectiveFeedbackPlan(_ feedback: IOSBackendObjectiveFeedback) async {
        actionError = nil
        feedbackPlanActionInProgressID = feedback.id
        defer { feedbackPlanActionInProgressID = nil }

        do {
            let result = try await store.regenerateObjectiveFeedbackPlan(
                objectiveId: displayedObjective.id,
                feedbackId: feedback.id
            )
            highlightedFeedbackID = result.objectiveFeedback.id
            await loadDetail(showSpinner: false)
            if result.objectiveFeedback.status == "queued" {
                await refreshDetailBurst()
            }
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private struct ObjectiveTaskCounts {
    let initialProposed: Int
    let followUpProposed: Int
    let proposed: Int
    let pending: Int
    let inProgress: Int
    let completed: Int
    let failed: Int

    init(tasks: [IOSBackendTask]) {
        self.initialProposed = tasks.filter { $0.status == "proposed" && $0.sourceFeedbackId == nil }.count
        self.followUpProposed = tasks.filter { $0.status == "proposed" && $0.sourceFeedbackId != nil }.count
        self.proposed = initialProposed + followUpProposed
        self.pending = tasks.filter { $0.status == "pending" }.count
        self.inProgress = tasks.filter { $0.status == "in_progress" }.count
        self.completed = tasks.filter { $0.status == "completed" }.count
        self.failed = tasks.filter { $0.status == "failed" }.count
    }

    var hasAnyTasks: Bool {
        proposed + pending + inProgress + completed + failed > 0
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
    let onlineAgentRegistrationsCount: Int
    let snapshotCount: Int
    let logCount: Int
    let lastLoadedAt: Date?
    var lastFinding: String? = nil
    var showsDisclosure = false
    var showsOperationalMetrics = true
    var statusPillLabel: String? = nil
    var statusPillTint: Color = .secondary

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

            if let statusPillLabel {
                Text(statusPillLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusPillTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusPillTint.opacity(0.14))
                    .clipShape(Capsule())
            }

            if showsOperationalMetrics {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if taskCounts.hasAnyTasks {
                            if taskCounts.proposed > 0 {
                                ObjectiveMetricChip(count: taskCounts.proposed, label: "proposed", tint: .teal)
                            }
                            if taskCounts.pending > 0 {
                                ObjectiveMetricChip(count: taskCounts.pending, label: "pending", tint: .orange)
                            }
                            if taskCounts.inProgress > 0 {
                                ObjectiveMetricChip(count: taskCounts.inProgress, label: "active", tint: .blue)
                            }
                            if taskCounts.completed > 0 {
                                ObjectiveMetricChip(count: taskCounts.completed, label: "done", tint: .green)
                            }
                            if taskCounts.failed > 0 {
                                ObjectiveMetricChip(count: taskCounts.failed, label: "failed", tint: .red)
                            }
                        }
                        if onlineAgentRegistrationsCount > 0 {
                            ObjectiveMetricChip(
                                count: onlineAgentRegistrationsCount,
                                label: onlineAgentRegistrationsCount == 1 ? "agent online" : "agents online",
                                tint: .teal
                            )
                        }
                        if snapshotCount > 0 {
                            ObjectiveMetricChip(count: snapshotCount, label: "snapshots", tint: .secondary)
                        }
                        if logCount > 0 {
                            ObjectiveMetricChip(count: logCount, label: "logs", tint: .secondary)
                        }
                    }
                }
            }

            if let lastFinding {
                Label(lastFinding, systemImage: "sparkle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

private struct ObjectiveIdleEmptyState: View {
    let idleReason: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No agents running")
                .font(.headline)
            if let idleReason {
                Text(idleReason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
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
    let count: Int
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 1) {
            Text("\(count)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(tint.opacity(0.8))
        }
        .frame(minWidth: 56)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        case "proposed": return .teal
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
            if task.sourceFeedbackId != nil {
                Text("Follow-up from feedback")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
            Text(ObjectiveFeedbackPresentation.findingTitle(for: snapshot.key))
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if ObjectiveFeedbackPresentation.findingTitle(for: snapshot.key) != snapshot.key {
                Text(snapshot.key)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(snapshot.value)
                .font(.subheadline)
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
