import Foundation
import PhotosUI
import SwiftUI
import UIKit

struct ObjectiveDetailView: View {
    let objective: IOSBackendObjective

    @Environment(ObjectivesStore.self) private var store
    @EnvironmentObject private var profileStore: FamilyProfileStore
    @State private var displayedObjective: IOSBackendObjective
    @State private var detail: IOSBackendObjectiveDetail?
    @State private var pollTask: Task<Void, Never>?
    @State private var isLoading = false
    @State private var isStartingWork = false
    @State private var actionInProgress: String?
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var showPromptSheet = false
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
    @State private var selectedFeedbackPhotoItems: [PhotosPickerItem] = []
    @State private var attachedFeedbackFileIds: [UUID] = []
    @State private var isUploadingFeedbackPhotos = false
    @State private var lastCompletedCount: Int = 0

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

    private var activeTasks: [IOSBackendTask] {
        tasks
            .filter { $0.status == "in_progress" }
            .sorted { latestActivityDate(for: $0) > latestActivityDate(for: $1) }
    }

    private var recentlyCompletedTasks: [IOSBackendTask] {
        tasks
            .filter { $0.status == "completed" }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var executionHealth: ObjectiveExecutionHealth {
        ObjectiveExecutionHealth.assess(
            objective: displayedObjective,
            tasks: tasks,
            agentLogs: agentLogs
        )
    }

    private var hasInProgressWork: Bool {
        executionHealth.hasInProgressWork
    }

    private var hasStaleActiveWork: Bool {
        executionHealth.hasStalledActiveWork
    }

    private var isActivelyRunningWork: Bool {
        hasInProgressWork && !hasStaleActiveWork
    }

    private var canDispatchQueuedTasksWhileActive: Bool {
        isActivelyRunningWork && taskCounts.pending > 0
    }

    private var actionsSectionTitle: String {
        if hasStaleActiveWork {
            return "Recovery"
        }
        if isActivelyRunningWork {
            return canDispatchQueuedTasksWhileActive ? "Manage Work" : "Recovery"
        }
        return "Actions"
    }

    private var nextCheckInEstimate: ObjectiveNextCheckInEstimate? {
        guard isActivelyRunningWork else { return nil }
        return estimateNextCheckIn()
    }

    private var activeWorkStatusPillLabel: String {
        hasStaleActiveWork ? "Needs attention" : "No action needed"
    }

    private var activeWorkStatusPillTint: Color {
        hasStaleActiveWork ? .orange : .blue
    }

    private var activeWorkActionLabel: String {
        hasStaleActiveWork ? "Work may be stalled" : "No action needed right now"
    }

    private var activeWorkActionIcon: String {
        hasStaleActiveWork ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var activeWorkActionTint: Color {
        hasStaleActiveWork ? .orange : .green
    }

    private var activeWorkActionMessage: String {
        if hasStaleActiveWork {
            let pendingMessage = taskCounts.pending > 0
                ? " \(taskCounts.pending) queued task(s) are waiting behind it."
                : ""
            let agentHint = onlineAgentRegistrationsCount == 0
                ? " The API also reports no online Mac agent right now."
                : ""
            return "The active task has not reported progress for about \(formattedStaleDuration(executionHealth.freshestActiveSilence)).\(pendingMessage) Use Reset stuck tasks & run below to requeue it and unblock the remaining research.\(agentHint)"
        }

        if canDispatchQueuedTasksWhileActive {
            return "\(taskCounts.inProgress) task(s) are already running. Use the button below only if you want to nudge the remaining queued task(s) onto the Mac."
        }

        return "\(taskCounts.inProgress) task(s) are already running on the Mac. Use the controls below only if progress looks stuck."
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
                label: ObjectiveFeedbackPresentation.targetLabel(for: $0, tasks: tasks),
                preview: ObjectiveFeedbackPresentation.previewText($0.value),
                researchSnapshotId: $0.id
            )
        })
        targets.append(contentsOf: tasks.prefix(8).map {
            ObjectiveFeedbackTarget(
                id: "task-\($0.id.uuidString)",
                label: ObjectiveFeedbackPresentation.taskLabel(for: $0),
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
        } else if hasInProgressWork {
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
                    nextCheckIn: nextCheckInEstimate,
                    statusPillLabel: activeWorkStatusPillLabel,
                    statusPillTint: activeWorkStatusPillTint
                )

                if !activeTasks.isEmpty {
                    ObjectiveLiveTaskGroup(
                        title: "Working On Now",
                        tasks: Array(activeTasks.prefix(3)),
                        rowBuilder: liveTaskRow
                    )
                }

                if !recentlyCompletedTasks.isEmpty {
                    ObjectiveLiveTaskGroup(
                        title: "Recently Finished",
                        tasks: Array(recentlyCompletedTasks.prefix(2)),
                        rowBuilder: completedTaskRow
                    )
                }

                if !snapshots.isEmpty {
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
                        Label("View Latest Research Details", systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
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
            Button {
                showPromptSheet = true
            } label: {
                Label("View prompt", systemImage: "doc.text.magnifyingglass")
            }
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

                PhotosPicker(
                    selection: $selectedFeedbackPhotoItems,
                    maxSelectionCount: 3,
                    matching: .images
                ) {
                    Label(
                        attachedFeedbackFileIds.isEmpty ? "Add Photos" : "\(attachedFeedbackFileIds.count) Photo\(attachedFeedbackFileIds.count == 1 ? "" : "s") Attached",
                        systemImage: attachedFeedbackFileIds.isEmpty ? "photo.badge.plus" : "photo.stack"
                    )
                }
                .onChange(of: selectedFeedbackPhotoItems) { _, newItems in
                    Task { await uploadFeedbackPhotos(newItems) }
                }

                if isUploadingFeedbackPhotos {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Uploading photos…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

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
                .disabled(trimmedFeedbackDraft.isEmpty || isSubmittingFeedback || isStartingWork || isDeleting || isUploadingFeedbackPhotos)
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
    private var compactStatusMessage: String {
        if hasStaleActiveWork {
            let agentHint = onlineAgentRegistrationsCount == 0 ? " No agent online." : ""
            return "Task stalled — use Reset below to unblock.\(agentHint)"
        }
        if canDispatchQueuedTasksWhileActive {
            return "\(taskCounts.inProgress) running · \(taskCounts.pending) queued"
        }
        return "\(taskCounts.inProgress) task(s) running on Mac"
    }

    @ViewBuilder
    private var actionsSectionContent: some View {
        if needsPlanReview {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
            if hasInProgressWork {
                Label(activeWorkActionLabel, systemImage: activeWorkActionIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(activeWorkActionTint)

                Text(compactStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if canDispatchQueuedTasksWhileActive {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        actionInProgress = "runNow"
                        Task { await runObjectiveNow() }
                    } label: {
                        HStack {
                            Label("Dispatch queued tasks now", systemImage: "paperplane.circle.fill")
                            if actionInProgress == "runNow" {
                                ProgressView().padding(.leading, 4)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isStartingWork || isDeleting)
                }
            } else {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
                .opacity(onlineAgentRegistrationsCount == 0 ? 0.55 : 1.0)
                .disabled(isStartingWork || isDeleting)
            }

            if hasInProgressWork {
                if hasStaleActiveWork {
                    Button {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
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
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(isStartingWork || isDeleting)
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
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
                    .buttonStyle(.bordered)
                    .disabled(isStartingWork || isDeleting)
                }
            }

            if displayedObjective.status == "active" {
                Button(role: .destructive) {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
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
        if hasStaleActiveWork {
            return "The active task has been quiet for about \(formattedStaleDuration(executionHealth.freshestActiveSilence)). Reset stuck tasks & run moves in-progress work back to pending and asks the Mac agent to pick it up again."
        }

        if needsPlanReview {
            return "Approve the proposed tasks to let the Mac agent begin. If the plan misses the mark, edit the prompt and regenerate it first."
        }

        if hasApprovedPlanWaitingToStart {
            return "This objective already has an approved plan. Start work when you're ready, or edit the prompt and regenerate the plan if you want a different breakdown."
        }

        if isActivelyRunningWork {
            if canDispatchQueuedTasksWhileActive {
                return "AgentKVT is already working. You do not need to press anything unless you want to dispatch the remaining queued tasks or recover from stalled work."
            }
            return "AgentKVT is already working. You do not need to press anything. Use these controls only if progress looks stuck."
        }

        switch displayedObjective.status {
        case "active":
            return "Run pending or failed tasks, reset stuck work, or rerun everything."
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
            if hasInProgressWork {
                if hasStaleActiveWork {
                    let queuedMessage = taskCounts.pending > 0
                        ? " \(taskCounts.pending) queued task(s) are still waiting behind it."
                        : ""
                    let agentHint = onlineAgentRegistrationsCount == 0
                        ? " The API also reports no online Mac agent right now."
                        : ""
                    return ObjectiveActivitySummary(
                        title: "Work looks stalled",
                        message: "The current in-progress task has not reported progress for about \(formattedStaleDuration(executionHealth.freshestActiveSilence)).\(queuedMessage) Use Reset stuck tasks & run below to requeue it and unblock the remaining research.\(agentHint)",
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .orange
                    )
                }
                let completedMessage = taskCounts.completed > 0
                    ? " \(taskCounts.completed) task(s) are already done."
                    : ""
                let queuedMessage = taskCounts.pending > 0
                    ? " \(taskCounts.pending) more queued."
                    : ""
                return ObjectiveActivitySummary(
                    title: "No action needed right now",
                    message: "AgentKVT is working on \(taskCounts.inProgress) task(s) right now.\(completedMessage)\(queuedMessage) Live task updates and your likely next check-in appear below.",
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
                    Text(actionsSectionTitle)
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
        .sheet(isPresented: $showPromptSheet) {
            ObjectivePromptSheet(prompt: displayedObjective.goal)
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
            detail = try await store.fetchDetail(for: displayedObjective.id, viewerProfileId: profileStore.currentProfileId)
            if let o = detail?.objective {
                displayedObjective = o
            }
            reconcileFeedbackTargetSelection()
            reconcileHighlightedFeedbackSelection()
            lastLoadedAt = Date()
            let newCompleted = taskCounts.completed
            if newCompleted > lastCompletedCount && lastCompletedCount > 0 {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            lastCompletedCount = newCompleted
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
                researchSnapshotId: selectedFeedbackTarget.researchSnapshotId,
                inboundFileIds: attachedFeedbackFileIds
            )
            highlightedFeedbackID = result.objectiveFeedback.id
            feedbackDraft = ""
            selectedFeedbackKind = ObjectiveFeedbackKindOption.followUp.rawValue
            selectedFeedbackTargetID = ObjectiveFeedbackTarget.objectiveID
            selectedFeedbackPhotoItems = []
            attachedFeedbackFileIds = []
            await loadDetail(showSpinner: false)
            if result.objectiveFeedback.status == "queued" {
                await refreshDetailBurst()
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func uploadFeedbackPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isUploadingFeedbackPhotos = true
        attachedFeedbackFileIds = []
        defer { isUploadingFeedbackPhotos = false }

        let sync = IOSBackendSyncService()
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let contentType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let fileName = "feedback_photo_\(UUID().uuidString).\(ext)"
                let uploaded = try await sync.createInboundFileRemote(
                    fileName: fileName,
                    contentType: contentType,
                    fileData: data,
                    uploadedByProfileId: nil
                )
                attachedFeedbackFileIds.append(uploaded.id)
            } catch {
                IOSRuntimeLog.log("[ObjectiveDetailView] photo upload failed: \(error)")
            }
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
            return ObjectiveFeedbackPresentation.targetLabel(for: snapshot, tasks: tasks)
        }
        if let taskId = feedback.taskId,
           let task = tasks.first(where: { $0.id == taskId }) {
            return ObjectiveFeedbackPresentation.taskLabel(for: task)
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

    private func latestActivityDate(for task: IOSBackendTask) -> Date {
        latestLog(for: task)?.timestamp ?? task.updatedAt
    }

    private func taskLogs(for task: IOSBackendTask) -> [IOSBackendAgentLog] {
        agentLogs
            .filter { log in logTaskID(for: log) == task.id }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func latestLog(for task: IOSBackendTask) -> IOSBackendAgentLog? {
        taskLogs(for: task).last
    }

    private func logTaskID(for log: IOSBackendAgentLog) -> UUID? {
        log.metadataJson["task_id"]?.stringValue.flatMap(UUID.init(uuidString:))
    }

    private func logWorkerLabel(for log: IOSBackendAgentLog) -> String? {
        log.metadataJson["worker_label"]?.stringValue
    }

    private func taskStartDate(for task: IOSBackendTask) -> Date? {
        let logs = taskLogs(for: task)
        if let claimDate = logs.first(where: { $0.phase == "worker_claim" })?.timestamp {
            return claimDate
        }
        return logs.first?.timestamp ?? task.createdAt
    }

    private func recentCompletedTaskDurations(limit: Int = 5) -> [TimeInterval] {
        Array(recentlyCompletedTasks.prefix(limit)).compactMap { task in
            guard let startDate = taskStartDate(for: task) else { return nil }
            let duration = task.updatedAt.timeIntervalSince(startDate)
            guard duration >= 30, duration <= 60 * 90 else { return nil }
            return duration
        }
    }

    private func activeElapsedTimes(referenceDate: Date = Date()) -> [TimeInterval] {
        activeTasks.compactMap { task in
            guard let startDate = taskStartDate(for: task) else { return nil }
            return max(0, referenceDate.timeIntervalSince(startDate))
        }
    }

    private func estimateNextCheckIn(referenceDate: Date = Date()) -> ObjectiveNextCheckInEstimate {
        let completedDurations = recentCompletedTaskDurations()
        let activeElapsed = activeElapsedTimes(referenceDate: referenceDate)
        let mostProgressedActive = activeElapsed.max() ?? 0

        guard !completedDurations.isEmpty else {
            return ObjectiveNextCheckInEstimate(
                title: "Likely next check-in",
                message: activeElapsed.isEmpty ? "Check back in a few minutes." : "Check back in a few minutes.",
                detail: "Timing will sharpen once a few more tasks finish.",
                tint: .blue
            )
        }

        let baseline = median(completedDurations)
        let spread: TimeInterval
        if completedDurations.count >= 3 {
            let sorted = completedDurations.sorted()
            let lowerIndex = max(0, Int(Double(sorted.count - 1) * 0.25))
            let upperIndex = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.75))
            spread = max(60, (sorted[upperIndex] - sorted[lowerIndex]) / 2)
        } else {
            spread = max(90, baseline * 0.35)
        }

        let center = max(60, baseline - mostProgressedActive)
        let lowerBound = max(60, center - spread)
        let upperBound = max(lowerBound + 60, center + spread)
        let detail = completedDurations.count >= 3
            ? "Based on the pace of the most recent completed tasks."
            : "Early estimate based on the latest finished work."

        return ObjectiveNextCheckInEstimate(
            title: "Likely next check-in",
            message: "Come back in about \(formattedCheckInRange(lowerBound, upperBound)).",
            detail: detail,
            tint: .blue
        )
    }

    private func median(_ values: [TimeInterval]) -> TimeInterval {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func formattedCheckInRange(_ lowerBound: TimeInterval, _ upperBound: TimeInterval) -> String {
        let lowerMinutes = max(1, Int((lowerBound / 60).rounded()))
        let upperMinutes = max(lowerMinutes, Int((upperBound / 60).rounded()))

        if upperMinutes <= 2 {
            return "1-2 min"
        }
        if upperMinutes < 60 {
            if upperMinutes - lowerMinutes <= 1 {
                return "\(upperMinutes) min"
            }
            return "\(lowerMinutes)-\(upperMinutes) min"
        }

        let lowerHours = Double(lowerMinutes) / 60
        let upperHours = Double(upperMinutes) / 60
        let lowerText = String(format: "%.1f", lowerHours)
        let upperText = String(format: "%.1f", upperHours)
        if lowerText == upperText {
            return "\(upperText) hr"
        }
        return "\(lowerText)-\(upperText) hr"
    }

    private func formattedStaleDuration(_ interval: TimeInterval?) -> String {
        guard let interval else { return "a while" }

        let roundedMinutes = max(1, Int((interval / 60).rounded()))
        if roundedMinutes < 60 {
            return roundedMinutes == 1 ? "1 min" : "\(roundedMinutes) min"
        }

        let hours = roundedMinutes / 60
        let minutes = roundedMinutes % 60
        if minutes == 0 {
            return hours == 1 ? "1 hr" : "\(hours) hr"
        }

        let hourPart = hours == 1 ? "1 hr" : "\(hours) hr"
        return "\(hourPart) \(minutes) min"
    }

    private func liveTaskMeta(for task: IOSBackendTask) -> String {
        guard let log = latestLog(for: task) else { return "Working now" }

        var parts: [String] = []
        if let workerLabel = logWorkerLabel(for: log) {
            parts.append(workerLabel)
        }
        parts.append(log.phase.replacingOccurrences(of: "_", with: " ").capitalized)
        return parts.joined(separator: " • ")
    }

    private func liveTaskSummary(for task: IOSBackendTask) -> String {
        guard let log = latestLog(for: task) else {
            return "AgentKVT is currently working on this task."
        }

        switch log.phase {
        case "worker_claim":
            return "Picked up by the Mac worker and actively running."
        case "tool_call":
            if let toolName = log.toolName, !toolName.isEmpty {
                return "Using \(humanizeToolName(toolName)) to move this task forward."
            }
            return "Running a tool for this task."
        case "tool_result":
            if let toolName = log.toolName, !toolName.isEmpty {
                return "Received results from \(humanizeToolName(toolName))."
            }
            return "Received fresh tool output for this task."
        case "assistant_final":
            return "Prepared a result summary and is wrapping this task up."
        case "objective_supervisor":
            return ObjectiveFeedbackPresentation.previewText(log.content, limit: 110)
                ?? "Supervisor updated this task."
        case "error":
            return ObjectiveFeedbackPresentation.previewText(log.content, limit: 110)
                ?? "This task hit an error."
        default:
            return ObjectiveFeedbackPresentation.previewText(log.content, limit: 110)
                ?? "Latest task update available."
        }
    }

    private func completedTaskSummary(for task: IOSBackendTask) -> String {
        if let resultSummary = ObjectiveFeedbackPresentation.previewText(task.resultSummary, limit: 110) {
            return resultSummary
        }
        return "Completed successfully."
    }

    private func humanizeToolName(_ toolName: String) -> String {
        toolName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    @ViewBuilder
    private func liveTaskRow(_ task: IOSBackendTask) -> some View {
        ObjectiveLiveTaskRow(
            title: task.description,
            meta: liveTaskMeta(for: task),
            detail: liveTaskSummary(for: task),
            timestamp: latestActivityDate(for: task),
            tint: .blue
        )
    }

    @ViewBuilder
    private func completedTaskRow(_ task: IOSBackendTask) -> some View {
        ObjectiveLiveTaskRow(
            title: task.description,
            meta: "Completed",
            detail: completedTaskSummary(for: task),
            timestamp: task.updatedAt,
            tint: .green
        )
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

private struct ObjectiveNextCheckInEstimate {
    let title: String
    let message: String
    let detail: String?
    let tint: Color
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
    var nextCheckIn: ObjectiveNextCheckInEstimate? = nil
    var statusPillLabel: String? = nil
    var statusPillTint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summary.systemImage)
                    .font(.title3)
                    .foregroundStyle(summary.tint)
                    .frame(width: 28)
                    .symbolEffect(.rotate, isActive: summary.showsProgress)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title)
                        .font(.headline)
                    Text(summary.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if onlineAgentRegistrationsCount > 0 {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: .green, radius: 3)
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

            if let nextCheckIn {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "clock.badge")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(nextCheckIn.tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(nextCheckIn.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(nextCheckIn.tint)

                        Text(nextCheckIn.message)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let detail = nextCheckIn.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if showsOperationalMetrics && taskCounts.hasAnyTasks {
                TaskProgressBar(taskCounts: taskCounts, snapshotCount: snapshotCount, logCount: logCount)
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

private struct TaskProgressBar: View {
    let taskCounts: ObjectiveTaskCounts
    let snapshotCount: Int
    let logCount: Int

    private var total: Int {
        taskCounts.proposed + taskCounts.pending + taskCounts.inProgress + taskCounts.completed + taskCounts.failed
    }

    private func fraction(_ count: Int) -> Double {
        total > 0 ? Double(count) / Double(total) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    let w = geo.size.width
                    if taskCounts.completed > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.green)
                            .frame(width: max(4, w * fraction(taskCounts.completed)))
                    }
                    if taskCounts.inProgress > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue)
                            .frame(width: max(4, w * fraction(taskCounts.inProgress)))
                    }
                    if taskCounts.pending + taskCounts.proposed > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: max(4, w * fraction(taskCounts.pending + taskCounts.proposed)))
                    }
                    if taskCounts.failed > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.red)
                            .frame(width: max(4, w * fraction(taskCounts.failed)))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 6)

            HStack {
                HStack(spacing: 6) {
                    if taskCounts.completed > 0 {
                        Text("\(taskCounts.completed) done")
                            .foregroundStyle(.green)
                    }
                    if taskCounts.inProgress > 0 {
                        Text("\(taskCounts.inProgress) active")
                            .foregroundStyle(.blue)
                    }
                    if taskCounts.pending > 0 {
                        Text("\(taskCounts.pending) pending")
                            .foregroundStyle(.secondary)
                    }
                    if taskCounts.proposed > 0 {
                        Text("\(taskCounts.proposed) proposed")
                            .foregroundStyle(.teal)
                    }
                    if taskCounts.failed > 0 {
                        Text("\(taskCounts.failed) failed")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption2)

                Spacer()

                HStack(spacing: 8) {
                    if snapshotCount > 0 {
                        Label("\(snapshotCount)", systemImage: "chart.bar.doc.horizontal")
                    }
                    if logCount > 0 {
                        Label("\(logCount)", systemImage: "list.bullet.rectangle")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct ObjectiveLiveTaskGroup<Content: View>: View {
    let title: String
    let tasks: [IOSBackendTask]
    @ViewBuilder let rowBuilder: (IOSBackendTask) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(tasks) { task in
                    rowBuilder(task)
                }
            }
        }
    }
}

private struct ObjectiveLiveTaskRow: View {
    let title: String
    let meta: String
    let detail: String
    let timestamp: Date
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text(timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(meta)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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

private struct ObjectivePromptSheet: View {
    let prompt: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(prompt)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

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

            if ObjectiveFeedbackPresentation.hasLowConfidence(snapshot.value) {
                Text("Low confidence")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.14))
                    .clipShape(Capsule())
            }

            let valueText = ObjectiveFeedbackPresentation.displayText(snapshot.value) ?? snapshot.value
            Text(LocalizedStringKey(valueText))
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
