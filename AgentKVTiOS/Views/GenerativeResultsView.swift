import SwiftUI

// MARK: - UINode model

struct UINode: Codable, Sendable {
    let type: String
    // Layout containers
    let children: [UINode]?
    // card
    let title: String?
    // text
    let content: String?
    let style: String?    // "headline" | "body" | "caption"
    // stat
    let label: String?
    let value: String?
    let delta: String?
    // badge
    let color: String?    // "green" | "red" | "orange" | "blue" | "gray"
}

struct UIPresentation: Codable, Sendable {
    let layout: UINode?
    let status: String?  // "ready" | "generating" — nil for legacy responses
}

struct ObjectiveFeedbackTarget: Identifiable, Hashable {
    static let objectiveID = "objective"

    let id: String
    let label: String
    var taskId: UUID? = nil
    var researchSnapshotId: UUID? = nil

    static func id(taskId: UUID?, researchSnapshotId: UUID?) -> String {
        if let researchSnapshotId {
            return "snapshot-\(researchSnapshotId.uuidString)"
        }
        if let taskId {
            return "task-\(taskId.uuidString)"
        }
        return ObjectiveFeedbackTarget.objectiveID
    }
}

struct ObjectiveFeedbackComposerContext: Identifiable {
    let id = UUID()
    let existingFeedback: IOSBackendObjectiveFeedback?
    let feedbackKind: String
    let targetID: String
    let draft: String
}

struct ObjectiveFeedbackSubmissionRequest: Sendable {
    let content: String
    let feedbackKind: String
    let taskId: UUID?
    let researchSnapshotId: UUID?
}

enum ObjectiveFeedbackKindOption: String, CaseIterable, Identifiable {
    case followUp = "follow_up"
    case compareOptions = "compare_options"
    case challengeResult = "challenge_result"
    case clarifyGaps = "clarify_gaps"
    case finalRecommendation = "final_recommendation"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .followUp: return "Go deeper"
        case .compareOptions: return "Compare options"
        case .challengeResult: return "Challenge result"
        case .clarifyGaps: return "Clarify gaps"
        case .finalRecommendation: return "Recommend next move"
        }
    }

    var systemImage: String {
        switch self {
        case .followUp: return "arrow.down.forward.circle"
        case .compareOptions: return "square.split.2x2"
        case .challengeResult: return "exclamationmark.bubble"
        case .clarifyGaps: return "questionmark.bubble"
        case .finalRecommendation: return "checkmark.seal"
        }
    }

    var tint: Color {
        switch self {
        case .followUp: return .blue
        case .compareOptions: return .teal
        case .challengeResult: return .orange
        case .clarifyGaps: return .purple
        case .finalRecommendation: return .green
        }
    }

    static func from(rawValue: String) -> ObjectiveFeedbackKindOption {
        ObjectiveFeedbackKindOption(rawValue: rawValue) ?? .followUp
    }
}

// MARK: - Node renderer

struct NodeView: View {
    let node: UINode

    var body: some View {
        switch node.type {
        case "vstack":
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array((node.children ?? []).enumerated()), id: \.offset) { _, child in
                    NodeView(node: child)
                }
            }
        case "hstack":
            HStack(alignment: .center, spacing: 8) {
                ForEach(Array((node.children ?? []).enumerated()), id: \.offset) { _, child in
                    NodeView(node: child)
                }
                Spacer(minLength: 0)
            }
        case "card":
            CardNodeView(node: node)
        case "text":
            TextNodeView(node: node)
        case "stat":
            StatNodeView(node: node)
        case "badge":
            BadgeNodeView(node: node)
        case "divider":
            Divider()
        default:
            EmptyView()
        }
    }
}

private struct CardNodeView: View {
    let node: UINode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = node.title {
                Text(title)
                    .font(.headline)
            }
            ForEach(Array((node.children ?? []).enumerated()), id: \.offset) { _, child in
                NodeView(node: child)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct TextNodeView: View {
    let node: UINode

    var body: some View {
        if let content = node.content {
            Text(content)
                .font(textFont)
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var textFont: Font {
        switch node.style {
        case "headline": return .headline
        case "caption":  return .caption
        default:         return .body
        }
    }

    private var textColor: Color {
        switch node.style {
        case "caption": return .secondary
        default:        return .primary
        }
    }
}

private struct StatNodeView: View {
    let node: UINode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label = node.label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let value = node.value {
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let delta = node.delta {
                Label(delta, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct BadgeNodeView: View {
    let node: UINode

    private var tint: Color {
        switch node.color {
        case "green":  return .green
        case "red":    return .red
        case "orange": return .orange
        case "blue":   return .blue
        default:       return .secondary
        }
    }

    var body: some View {
        if let label = node.label {
            Text(label)
                .font(.caption)
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.12))
                .clipShape(Capsule())
        }
    }
}

struct ObjectiveFeedbackComposerSheet: View {
    let objectiveId: UUID
    let objectiveGoal: String
    let objectiveStatus: String
    let tasks: [IOSBackendTask]
    let snapshots: [IOSBackendResearchSnapshot]
    let editingFeedback: IOSBackendObjectiveFeedback?
    var onSubmitted: ((IOSBackendSubmitObjectiveFeedbackResult) -> Void)? = nil
    var onCreateRequested: ((ObjectiveFeedbackSubmissionRequest) -> Void)? = nil

    @Environment(ObjectivesStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var feedbackDraft = ""
    @State private var selectedFeedbackKind = ObjectiveFeedbackKindOption.followUp.rawValue
    @State private var selectedFeedbackTargetID = ObjectiveFeedbackTarget.objectiveID
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(
        objectiveId: UUID,
        objectiveGoal: String,
        objectiveStatus: String,
        tasks: [IOSBackendTask],
        snapshots: [IOSBackendResearchSnapshot],
        editingFeedback: IOSBackendObjectiveFeedback? = nil,
        initialFeedbackKind: String = ObjectiveFeedbackKindOption.followUp.rawValue,
        initialFeedbackTargetID: String = ObjectiveFeedbackTarget.objectiveID,
        initialFeedbackDraft: String = "",
        onSubmitted: ((IOSBackendSubmitObjectiveFeedbackResult) -> Void)? = nil,
        onCreateRequested: ((ObjectiveFeedbackSubmissionRequest) -> Void)? = nil
    ) {
        self.objectiveId = objectiveId
        self.objectiveGoal = objectiveGoal
        self.objectiveStatus = objectiveStatus
        self.tasks = tasks
        self.snapshots = snapshots
        self.editingFeedback = editingFeedback
        self.onSubmitted = onSubmitted
        self.onCreateRequested = onCreateRequested
        _selectedFeedbackKind = State(initialValue: initialFeedbackKind)
        _selectedFeedbackTargetID = State(initialValue: initialFeedbackTargetID)
        _feedbackDraft = State(initialValue: initialFeedbackDraft)
    }

    private var title: String {
        editingFeedback == nil ? "Continue Research" : "Edit Follow-up Plan"
    }

    private var submitLabel: String {
        editingFeedback == nil ? "Create follow-up tasks" : "Update follow-up plan"
    }

    private var trimmedFeedbackDraft: String {
        feedbackDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var submissionRequest: ObjectiveFeedbackSubmissionRequest {
        ObjectiveFeedbackSubmissionRequest(
            content: trimmedFeedbackDraft,
            feedbackKind: selectedFeedbackKind,
            taskId: selectedFeedbackTarget.taskId,
            researchSnapshotId: selectedFeedbackTarget.researchSnapshotId
        )
    }

    private var feedbackTargets: [ObjectiveFeedbackTarget] {
        var targets = [ObjectiveFeedbackTarget(id: ObjectiveFeedbackTarget.objectiveID, label: "Entire objective")]
        targets.append(contentsOf: snapshots.prefix(8).map {
            ObjectiveFeedbackTarget(
                id: "snapshot-\($0.id.uuidString)",
                label: "Finding: \($0.key)",
                researchSnapshotId: $0.id
            )
        })
        targets.append(contentsOf: tasks.prefix(8).map {
            ObjectiveFeedbackTarget(
                id: "task-\($0.id.uuidString)",
                label: "Task: \($0.description)",
                taskId: $0.id
            )
        })
        return targets
    }

    private var selectedFeedbackTarget: ObjectiveFeedbackTarget {
        feedbackTargets.first(where: { $0.id == selectedFeedbackTargetID })
            ?? feedbackTargets.first
            ?? .init(id: ObjectiveFeedbackTarget.objectiveID, label: "Entire objective")
    }

    private var footerCopy: String {
        if editingFeedback == nil, onCreateRequested != nil {
            if objectiveStatus == "active" {
                return "Submitting follow-up tasks closes this sheet right away. The Research screen will keep updating while approved work gets picked up."
            }
            return "Submitting follow-up tasks closes this sheet right away. The Research screen will keep updating while the next plan is prepared."
        }
        if objectiveStatus == "active" {
            return "Active objectives queue approved follow-up tasks automatically so the agent can keep going."
        }
        return "Pending objectives save approved follow-up tasks for later, and larger batches stay under review until you approve them."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(objectiveGoal)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Objective")
                }

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
                        .lineLimit(4...8)

                    Button {
                        if editingFeedback == nil, let onCreateRequested {
                            errorMessage = nil
                            onCreateRequested(submissionRequest)
                            dismiss()
                        } else {
                            Task { await submit() }
                        }
                    } label: {
                        HStack {
                            Label(submitLabel, systemImage: "arrow.triangle.branch")
                            if isSubmitting {
                                ProgressView()
                                    .padding(.leading, 4)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ObjectiveFeedbackKindOption.from(rawValue: selectedFeedbackKind).tint)
                    .disabled(trimmedFeedbackDraft.isEmpty || isSubmitting)
                } header: {
                    Text("Next Step")
                } footer: {
                    Text(footerCopy)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Could Not Submit Feedback", isPresented: Binding(
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
    private func submit() async {
        guard !trimmedFeedbackDraft.isEmpty else { return }

        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let result: IOSBackendSubmitObjectiveFeedbackResult
            if let editingFeedback {
                result = try await store.updateObjectiveFeedback(
                    objectiveId: objectiveId,
                    feedbackId: editingFeedback.id,
                    content: submissionRequest.content,
                    feedbackKind: submissionRequest.feedbackKind,
                    taskId: submissionRequest.taskId,
                    researchSnapshotId: submissionRequest.researchSnapshotId
                )
            } else {
                result = try await store.submitObjectiveFeedback(
                    id: objectiveId,
                    content: submissionRequest.content,
                    feedbackKind: submissionRequest.feedbackKind,
                    taskId: submissionRequest.taskId,
                    researchSnapshotId: submissionRequest.researchSnapshotId
                )
            }
            onSubmitted?(result)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ObjectiveFeedbackPlanCard: View {
    let feedback: IOSBackendObjectiveFeedback
    let targetLabel: String
    let objectiveStatus: String
    let followUpTasks: [IOSBackendTask]
    var isHighlighted = false
    var isWorking = false
    var onApprove: (() -> Void)? = nil
    var onRegenerate: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil

    private var kind: ObjectiveFeedbackKindOption {
        .from(rawValue: feedback.feedbackKind)
    }

    private var statusColor: Color {
        switch feedback.status {
        case "review_required": return .teal
        case "queued": return .blue
        case "planned": return .orange
        case "completed": return .green
        case "failed": return .red
        default: return .secondary
        }
    }

    private var statusLabel: String {
        feedback.status.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var shouldShowTasks: Bool {
        !followUpTasks.isEmpty && (isHighlighted || feedback.status == "review_required" || feedback.status == "completed")
    }

    private var approvalLabel: String {
        objectiveStatus == "active" ? "Approve & queue" : "Approve"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(kind.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(kind.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(kind.tint.opacity(0.14))
                    .clipShape(Capsule())

                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)

                Spacer()

                if feedback.status == "completed", let completedAt = feedback.completedAt {
                    Text(completedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(feedback.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(targetLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(feedback.content)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if followUpTasks.count > 0 {
                Text("\(followUpTasks.count) follow-up task(s) created")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if shouldShowTasks {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(followUpTasks) { task in
                        TaskRow(task: task)
                    }
                }
                .padding(10)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let completionSummary = feedback.completionSummary, !completionSummary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What changed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(completionSummary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if feedback.status == "review_required" {
                Text("Review this batch before AgentKVT starts the next pass.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        if let onApprove {
                            actionButton(
                                title: approvalLabel,
                                systemImage: "checkmark.circle.fill",
                                prominent: true,
                                tint: .blue,
                                fullWidth: false,
                                action: onApprove
                            )
                        }

                        if let onRegenerate {
                            actionButton(
                                title: "Regenerate",
                                systemImage: "arrow.trianglehead.clockwise",
                                fullWidth: false,
                                action: onRegenerate
                            )
                        }

                        if let onEdit {
                            actionButton(
                                title: "Edit",
                                systemImage: "pencil",
                                fullWidth: false,
                                action: onEdit
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if let onApprove {
                            actionButton(
                                title: approvalLabel,
                                systemImage: "checkmark.circle.fill",
                                prominent: true,
                                tint: .blue,
                                fullWidth: true,
                                action: onApprove
                            )
                        }

                        if let onRegenerate {
                            actionButton(
                                title: "Regenerate",
                                systemImage: "arrow.trianglehead.clockwise",
                                fullWidth: true,
                                action: onRegenerate
                            )
                        }

                        if let onEdit {
                            actionButton(
                                title: "Edit",
                                systemImage: "pencil",
                                fullWidth: true,
                                action: onEdit
                            )
                        }
                    }
                }
                .disabled(isWorking)

                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        systemImage: String,
        prominent: Bool = false,
        tint: Color? = nil,
        fullWidth: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: !fullWidth, vertical: false)
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }

        if prominent {
            let styledButton = button.buttonStyle(.borderedProminent)
            if let tint {
                styledButton.tint(tint)
            } else {
                styledButton
            }
        } else {
            let styledButton = button.buttonStyle(.bordered)
            if let tint {
                styledButton.tint(tint)
            } else {
                styledButton
            }
        }
    }
}

private struct ResultsFindingFollowUpCard: View {
    let snapshot: IOSBackendResearchSnapshot
    var onSelectAction: (ObjectiveFeedbackComposerContext) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SnapshotRow(snapshot: snapshot)

            VStack(alignment: .leading, spacing: 8) {
                Text("Next action")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    quickActionButton(label: "Approve", tint: .green) {
                        onSelectAction(context(kind: .finalRecommendation, draft: "This finding looks right. Use it and turn it into the next recommendation or decision."))
                    }
                    quickActionButton(label: "Go deeper", tint: .blue) {
                        onSelectAction(context(kind: .followUp, draft: "Go deeper on this finding and expand the most important details we still need."))
                    }
                }

                HStack(spacing: 8) {
                    quickActionButton(label: "Compare", tint: .teal) {
                        onSelectAction(context(kind: .compareOptions, draft: "Compare this finding against the strongest alternative and explain which option wins."))
                    }
                    quickActionButton(label: "Challenge", tint: .orange) {
                        onSelectAction(context(kind: .challengeResult, draft: "Challenge this finding, verify the assumptions, and tell me what might be wrong."))
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func context(kind: ObjectiveFeedbackKindOption, draft: String) -> ObjectiveFeedbackComposerContext {
        ObjectiveFeedbackComposerContext(
            existingFeedback: nil,
            feedbackKind: kind.rawValue,
            targetID: ObjectiveFeedbackTarget.id(taskId: nil, researchSnapshotId: snapshot.id),
            draft: draft
        )
    }

    @ViewBuilder
    private func quickActionButton(label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }
}

// MARK: - Generative results view

struct GenerativeResultsView: View {
    let objectiveId: UUID
    let objectiveGoal: String
    let objectiveStatus: String
    let tasks: [IOSBackendTask]
    let snapshots: [IOSBackendResearchSnapshot]
    let onlineAgentRegistrationsCount: Int
    var onFeedbackMutated: (() -> Void)? = nil

    @Environment(ObjectivesStore.self) private var store
    @State private var layout: UINode?
    @State private var isLoading = false
    @State private var useFallback = false
    @State private var composerContext: ObjectiveFeedbackComposerContext?
    @State private var latestFeedbackResult: IOSBackendSubmitObjectiveFeedbackResult?
    @State private var feedbackSuccessMessage: String?
    @State private var feedbackErrorMessage: String?
    @State private var activeFeedbackAction: String?
    @State private var activityDetail: IOSBackendObjectiveDetail?
    @State private var isSubmittingFollowUpInBackground = false
    @State private var inlineActivityMessage: String?
    @State private var activityPollTask: Task<Void, Never>?
    @State private var activityPollToken = UUID()
    @State private var activityPollUntil: Date?

    private var canContinueResearch: Bool {
        objectiveStatus == "pending" || objectiveStatus == "active"
    }

    private var quickFeedbackKinds: [ObjectiveFeedbackKindOption] {
        [.followUp, .compareOptions, .challengeResult]
    }

    private var activityTasks: [IOSBackendTask] {
        activityDetail?.tasks ?? tasks
    }

    private var onlineAgentsCount: Int {
        activityDetail?.onlineAgentRegistrationsCount ?? onlineAgentRegistrationsCount
    }

    private var runningTaskCount: Int {
        activityTasks.filter { $0.status == "in_progress" }.count
    }

    private var queuedTaskCount: Int {
        activityTasks.filter { $0.status == "pending" }.count
    }

    private var shouldShowAgentActivity: Bool {
        isSubmittingFollowUpInBackground ||
            inlineActivityMessage != nil ||
            runningTaskCount > 0 ||
            queuedTaskCount > 0 ||
            onlineAgentsCount > 0
    }

    private var shouldPollAgentActivity: Bool {
        isSubmittingFollowUpInBackground ||
            runningTaskCount > 0 ||
            queuedTaskCount > 0 ||
            (activityPollUntil.map { $0 > Date() } ?? false)
    }

    private var agentActivityMessage: String {
        if isSubmittingFollowUpInBackground {
            return "Creating follow-up tasks in the background. You can keep browsing while this screen refreshes activity."
        }
        if runningTaskCount > 0 {
            return "\(runningTaskCount) task(s) are currently running."
        }
        if queuedTaskCount > 0 {
            if onlineAgentsCount > 0 {
                return "\(queuedTaskCount) task(s) are queued and ready for the next available agent."
            }
            return "\(queuedTaskCount) task(s) are queued. No agent looks online yet."
        }
        if let inlineActivityMessage {
            return inlineActivityMessage
        }
        if onlineAgentsCount > 0 {
            return "\(onlineAgentsCount) agent(s) are online and ready for work."
        }
        return "No active agent work yet."
    }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Generating layout…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let layout, !useFallback {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        NodeView(node: layout)

                        if shouldShowAgentActivity {
                            ResearchAgentActivityCard(
                                runningTaskCount: runningTaskCount,
                                queuedTaskCount: queuedTaskCount,
                                onlineAgentsCount: onlineAgentsCount,
                                message: agentActivityMessage,
                                showsProgress: isSubmittingFollowUpInBackground
                            )
                        }

                        if let latestFeedbackResult {
                            latestFeedbackPlanCard(for: latestFeedbackResult)
                        }

                        if canContinueResearch && !snapshots.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Continue from a finding")
                                    .font(.headline)
                                ForEach(snapshots) { snapshot in
                                    ResultsFindingFollowUpCard(snapshot: snapshot) { context in
                                        composerContext = context
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
            } else {
                List {
                    if shouldShowAgentActivity {
                        Section("Agent Activity") {
                            ResearchAgentActivityCard(
                                runningTaskCount: runningTaskCount,
                                queuedTaskCount: queuedTaskCount,
                                onlineAgentsCount: onlineAgentsCount,
                                message: agentActivityMessage,
                                showsProgress: isSubmittingFollowUpInBackground
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                        }
                    }

                    if let latestFeedbackResult {
                        Section("Latest Follow-up Plan") {
                            latestFeedbackPlanCard(for: latestFeedbackResult)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                        }
                    }

                    Section("Research Snapshots") {
                        if snapshots.isEmpty {
                            Text("No research data yet.")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        } else {
                            ForEach(snapshots) { snapshot in
                                if canContinueResearch {
                                    ResultsFindingFollowUpCard(snapshot: snapshot) { context in
                                        composerContext = context
                                    }
                                } else {
                                    SnapshotRow(snapshot: snapshot)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Research")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isLoading {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await loadPresentation()
                            await refreshActivityStatus()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if canContinueResearch && !isLoading {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Guide the next pass")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(quickFeedbackKinds) { option in
                                    Button {
                                        composerContext = ObjectiveFeedbackComposerContext(
                                            existingFeedback: nil,
                                            feedbackKind: option.rawValue,
                                            targetID: ObjectiveFeedbackTarget.objectiveID,
                                            draft: ""
                                        )
                                    } label: {
                                        Label(option.label, systemImage: option.systemImage)
                                            .font(.subheadline.weight(.medium))
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(option.tint)
                                }
                            }
                            .padding(.trailing, 2)
                        }

                        Button {
                            composerContext = ObjectiveFeedbackComposerContext(
                                existingFeedback: nil,
                                feedbackKind: ObjectiveFeedbackKindOption.followUp.rawValue,
                                targetID: ObjectiveFeedbackTarget.objectiveID,
                                draft: ""
                            )
                        } label: {
                            Label("Continue Research", systemImage: "arrow.triangle.branch")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .background(.regularMaterial)
            }
        }
        .sheet(item: $composerContext) { context in
            ObjectiveFeedbackComposerSheet(
                objectiveId: objectiveId,
                objectiveGoal: objectiveGoal,
                objectiveStatus: objectiveStatus,
                tasks: tasks,
                snapshots: snapshots,
                editingFeedback: context.existingFeedback,
                initialFeedbackKind: context.feedbackKind,
                initialFeedbackTargetID: context.targetID,
                initialFeedbackDraft: context.draft,
                onSubmitted: { result in
                    latestFeedbackResult = result
                    feedbackSuccessMessage = successMessage(for: result.objectiveFeedback.status)
                    onFeedbackMutated?()
                },
                onCreateRequested: { request in
                    submitFeedbackInBackground(request)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Research Updated", isPresented: Binding(
            get: { feedbackSuccessMessage != nil },
            set: { if !$0 { feedbackSuccessMessage = nil } }
        )) {
            Button("OK", role: .cancel) { feedbackSuccessMessage = nil }
        } message: {
            Text(feedbackSuccessMessage ?? "An error occurred.")
        }
        .alert("Could Not Update Follow-up Plan", isPresented: Binding(
            get: { feedbackErrorMessage != nil },
            set: { if !$0 { feedbackErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { feedbackErrorMessage = nil }
        } message: {
            Text(feedbackErrorMessage ?? "An error occurred.")
        }
        .task {
            await loadPresentation()
            await refreshActivityStatus()
            reconcileActivityPolling()
        }
        .onChange(of: shouldPollAgentActivity) { _, _ in
            reconcileActivityPolling()
        }
        .onDisappear {
            activityPollTask?.cancel()
            activityPollTask = nil
        }
    }

    private func feedbackTargetLabel(for feedback: IOSBackendObjectiveFeedback) -> String {
        if let snapshotId = feedback.researchSnapshotId,
           let snapshot = snapshots.first(where: { $0.id == snapshotId }) {
            return "Finding: \(snapshot.key)"
        }
        if let taskId = feedback.taskId,
           let task = tasks.first(where: { $0.id == taskId }) {
            return "Task: \(task.description)"
        }
        return "Entire objective"
    }

    @ViewBuilder
    private func latestFeedbackPlanCard(for result: IOSBackendSubmitObjectiveFeedbackResult) -> some View {
        let feedback = result.objectiveFeedback
        let requiresReview = feedback.status == "review_required"

        ObjectiveFeedbackPlanCard(
            feedback: feedback,
            targetLabel: feedbackTargetLabel(for: feedback),
            objectiveStatus: objectiveStatus,
            followUpTasks: result.followUpTasks,
            isHighlighted: true,
            isWorking: activeFeedbackAction != nil,
            onApprove: requiresReview ? {
                Task { await approveLatestFeedbackPlan() }
            } : nil,
            onRegenerate: requiresReview ? {
                Task { await regenerateLatestFeedbackPlan() }
            } : nil,
            onEdit: requiresReview ? {
                composerContext = composerContext(for: feedback)
            } : nil
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

    private func successMessage(for status: String) -> String {
        switch status {
        case "review_required":
            return "Your follow-up plan is ready for review."
        case "queued":
            return "Follow-up tasks were queued for the agent."
        case "planned":
            return "Follow-up tasks were added to this objective for later review."
        case "completed":
            return "This follow-up batch is already complete."
        default:
            return "Research updated."
        }
    }

    private func inlineMessage(for status: String) -> String {
        switch status {
        case "review_required":
            return "The follow-up plan is ready for review."
        case "queued":
            return "Follow-up tasks were queued. Agent activity below will refresh automatically."
        case "planned":
            return "Follow-up tasks were added and saved for later review."
        case "completed":
            return "This follow-up batch is already complete."
        default:
            return "Research activity updated."
        }
    }

    @MainActor
    private func approveLatestFeedbackPlan() async {
        guard let feedback = latestFeedbackResult?.objectiveFeedback else { return }
        feedbackErrorMessage = nil
        activeFeedbackAction = "approve"
        defer { activeFeedbackAction = nil }

        do {
            let result = try await store.approveObjectiveFeedbackPlan(objectiveId: objectiveId, feedbackId: feedback.id)
            latestFeedbackResult = result
            feedbackSuccessMessage = successMessage(for: result.objectiveFeedback.status)
            onFeedbackMutated?()
            await refreshActivityStatus()
            extendActivityPolling()
            reconcileActivityPolling()
        } catch {
            feedbackErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func regenerateLatestFeedbackPlan() async {
        guard let feedback = latestFeedbackResult?.objectiveFeedback else { return }
        feedbackErrorMessage = nil
        activeFeedbackAction = "regenerate"
        defer { activeFeedbackAction = nil }

        do {
            let result = try await store.regenerateObjectiveFeedbackPlan(objectiveId: objectiveId, feedbackId: feedback.id)
            latestFeedbackResult = result
            feedbackSuccessMessage = successMessage(for: result.objectiveFeedback.status)
            onFeedbackMutated?()
            await refreshActivityStatus()
            extendActivityPolling()
            reconcileActivityPolling()
        } catch {
            feedbackErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func submitFeedbackInBackground(_ request: ObjectiveFeedbackSubmissionRequest) {
        feedbackErrorMessage = nil
        feedbackSuccessMessage = nil
        inlineActivityMessage = nil
        isSubmittingFollowUpInBackground = true
        extendActivityPolling()
        reconcileActivityPolling()

        Task {
            do {
                let result = try await store.submitObjectiveFeedback(
                    id: objectiveId,
                    content: request.content,
                    feedbackKind: request.feedbackKind,
                    taskId: request.taskId,
                    researchSnapshotId: request.researchSnapshotId
                )
                latestFeedbackResult = result
                inlineActivityMessage = inlineMessage(for: result.objectiveFeedback.status)
                isSubmittingFollowUpInBackground = false
                onFeedbackMutated?()
                await refreshActivityStatus()
                extendActivityPolling()
                reconcileActivityPolling()
            } catch {
                isSubmittingFollowUpInBackground = false
                if isTimeoutError(error) {
                    inlineActivityMessage = "This request is taking longer than expected. The Research screen will keep refreshing activity."
                    extendActivityPolling()
                    reconcileActivityPolling()
                    await refreshActivityStatus()
                } else {
                    feedbackErrorMessage = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    private func loadPresentation() async {
        isLoading = true
        useFallback = false
        layout = nil
        defer { isLoading = false }

        do {
            let result = try await store.fetchPresentation(for: objectiveId)
            if let node = result.layout {
                layout = node
            } else if result.status == "generating" {
                // Server enqueued a generation job — poll every 5s until ready or 60s elapsed
                for _ in 0..<12 {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    let retry = try await store.fetchPresentation(for: objectiveId)
                    if let node = retry.layout {
                        layout = node
                        return
                    }
                    if retry.status != "generating" { break }
                }
                useFallback = true
            } else {
                useFallback = true
            }
        } catch {
            IOSRuntimeLog.log("[GenerativeResultsView] Presentation fetch failed: \(error)")
            useFallback = true
        }
    }

    @MainActor
    private func refreshActivityStatus() async {
        do {
            activityDetail = try await store.fetchDetail(for: objectiveId)
        } catch {
            IOSRuntimeLog.log("[GenerativeResultsView] Activity refresh failed: \(error)")
        }
    }

    @MainActor
    private func reconcileActivityPolling() {
        guard shouldPollAgentActivity else {
            activityPollTask?.cancel()
            activityPollTask = nil
            return
        }
        guard activityPollTask == nil else { return }

        let token = UUID()
        activityPollToken = token
        activityPollTask = Task {
            while !Task.isCancelled {
                await refreshActivityStatus()
                let shouldContinue = await MainActor.run { shouldPollAgentActivity }
                if !shouldContinue { break }
                try? await Task.sleep(for: .seconds(4))
            }

            await MainActor.run {
                if activityPollToken == token {
                    activityPollTask = nil
                }
            }
        }
    }

    @MainActor
    private func extendActivityPolling(seconds: TimeInterval = 150) {
        let nextDeadline = Date().addingTimeInterval(seconds)
        if let currentDeadline = activityPollUntil, currentDeadline > nextDeadline {
            return
        }
        activityPollUntil = nextDeadline
    }

    private func isTimeoutError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code == .timedOut
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == URLError.timedOut.rawValue
    }
}

private struct ResearchAgentActivityCard: View {
    let runningTaskCount: Int
    let queuedTaskCount: Int
    let onlineAgentsCount: Int
    let message: String
    let showsProgress: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: showsProgress ? "arrow.triangle.branch.circle.fill" : "bolt.horizontal.circle.fill")
                    .font(.title3)
                    .foregroundStyle(showsProgress ? .teal : .blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Agent Activity")
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if showsProgress {
                    ProgressView()
                }
            }

            HStack(spacing: 8) {
                ResearchAgentActivityMetric(
                    count: runningTaskCount,
                    label: runningTaskCount == 1 ? "running task" : "running tasks",
                    tint: runningTaskCount > 0 ? .blue : .secondary
                )
                ResearchAgentActivityMetric(
                    count: queuedTaskCount,
                    label: queuedTaskCount == 1 ? "queued task" : "queued tasks",
                    tint: queuedTaskCount > 0 ? .orange : .secondary
                )
                ResearchAgentActivityMetric(
                    count: onlineAgentsCount,
                    label: onlineAgentsCount == 1 ? "agent online" : "agents online",
                    tint: onlineAgentsCount > 0 ? .green : .secondary
                )
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ResearchAgentActivityMetric: View {
    let count: Int
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(count)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
