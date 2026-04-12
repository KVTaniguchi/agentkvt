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
    let preview: String?
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
    let targetLabel: String
    let targetPreview: String?
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

enum ObjectiveFeedbackPresentation {
    static func findingTitle(for key: String) -> String {
        let cleaned = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return "Untitled finding" }

        let collapsed = cleaned.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        return collapsed.prefix(1).capitalized + collapsed.dropFirst()
    }

    static func targetLabel(for snapshot: IOSBackendResearchSnapshot) -> String {
        "Finding: \(findingTitle(for: snapshot.key))"
    }

    static func previewText(_ text: String?, limit: Int = 140) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    static func statusColor(for status: String) -> Color {
        switch status {
        case "review_required": return .teal
        case "queued": return .blue
        case "planned": return .orange
        case "completed": return .green
        case "failed": return .red
        case "submitting": return .blue
        case "received_building_plan": return .teal
        case "timed_out_but_refreshing": return .orange
        default: return .secondary
        }
    }

    static func statusLabel(for status: String) -> String {
        switch status {
        case "review_required": return "Ready for review"
        case "queued": return "Queued for agent"
        case "planned": return "Saved for later"
        case "completed": return "Completed"
        case "failed": return "Needs attention"
        case "submitting": return "Sending feedback"
        case "received_building_plan": return "Creating next pass"
        case "timed_out_but_refreshing": return "Still working"
        default:
            return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func statusMessage(for status: String, objectiveStatus: String) -> String? {
        switch status {
        case "review_required":
            return "Review this next pass before AgentKVT keeps going."
        case "queued":
            if objectiveStatus == "active" {
                return "This next pass is queued for the agent and will start as capacity opens up."
            }
            return "This next pass is ready and will begin when you start work."
        case "planned":
            return "This next pass was saved to the objective for later review."
        case "completed":
            return "This follow-up batch already finished."
        case "failed":
            return "This follow-up needs attention before it can continue."
        case "submitting":
            return "Sending your feedback to AgentKVT."
        case "received_building_plan":
            return "Feedback received. Building the next pass now."
        case "timed_out_but_refreshing":
            return "This is taking longer than expected. The Research screen will keep refreshing."
        default:
            return nil
        }
    }
}

struct ObjectiveFeedbackCardModel: Identifiable, Sendable {
    let id: String
    let feedbackId: UUID?
    let feedbackKind: String
    let status: String
    let content: String
    let createdAt: Date
    let completedAt: Date?
    let completionSummary: String?
    let targetLabel: String
    let targetPreview: String?
    let followUpTasks: [IOSBackendTask]

    init(
        id: String,
        feedbackId: UUID?,
        feedbackKind: String,
        status: String,
        content: String,
        createdAt: Date,
        completedAt: Date? = nil,
        completionSummary: String? = nil,
        targetLabel: String,
        targetPreview: String? = nil,
        followUpTasks: [IOSBackendTask] = []
    ) {
        self.id = id
        self.feedbackId = feedbackId
        self.feedbackKind = feedbackKind
        self.status = status
        self.content = content
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.completionSummary = completionSummary
        self.targetLabel = targetLabel
        self.targetPreview = targetPreview
        self.followUpTasks = followUpTasks
    }

    init(
        feedback: IOSBackendObjectiveFeedback,
        targetLabel: String,
        targetPreview: String? = nil,
        followUpTasks: [IOSBackendTask] = []
    ) {
        self.init(
            id: feedback.id.uuidString,
            feedbackId: feedback.id,
            feedbackKind: feedback.feedbackKind,
            status: feedback.status,
            content: feedback.content,
            createdAt: feedback.createdAt,
            completedAt: feedback.completedAt,
            completionSummary: feedback.completionSummary,
            targetLabel: targetLabel,
            targetPreview: targetPreview,
            followUpTasks: followUpTasks
        )
    }

    static func pending(from request: ObjectiveFeedbackSubmissionRequest, status: String, createdAt: Date) -> ObjectiveFeedbackCardModel {
        ObjectiveFeedbackCardModel(
            id: "pending-\(createdAt.timeIntervalSince1970)",
            feedbackId: nil,
            feedbackKind: request.feedbackKind,
            status: status,
            content: request.content,
            createdAt: createdAt,
            targetLabel: request.targetLabel,
            targetPreview: ObjectiveFeedbackPresentation.previewText(request.targetPreview),
            followUpTasks: []
        )
    }
}

struct ObjectiveFeedbackPendingSubmission: Identifiable, Sendable {
    let id = UUID()
    let request: ObjectiveFeedbackSubmissionRequest
    let card: ObjectiveFeedbackCardModel
    let submittedAt: Date
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
    var onTimedOut: ((ObjectiveFeedbackPendingSubmission) -> Void)? = nil

    @Environment(ObjectivesStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var feedbackDraft = ""
    @State private var selectedFeedbackKind = ObjectiveFeedbackKindOption.followUp.rawValue
    @State private var selectedFeedbackTargetID = ObjectiveFeedbackTarget.objectiveID
    @State private var errorMessage: String?
    @State private var submissionPhase: SubmissionPhase = .editing

    private enum SubmissionPhase {
        case editing
        case submitting
        case receivedBuildingPlan
        case success(IOSBackendSubmitObjectiveFeedbackResult)
        case timedOut(ObjectiveFeedbackPendingSubmission)
    }

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
        onTimedOut: ((ObjectiveFeedbackPendingSubmission) -> Void)? = nil
    ) {
        self.objectiveId = objectiveId
        self.objectiveGoal = objectiveGoal
        self.objectiveStatus = objectiveStatus
        self.tasks = tasks
        self.snapshots = snapshots
        self.editingFeedback = editingFeedback
        self.onSubmitted = onSubmitted
        self.onTimedOut = onTimedOut
        _selectedFeedbackKind = State(initialValue: initialFeedbackKind)
        _selectedFeedbackTargetID = State(initialValue: initialFeedbackTargetID)
        _feedbackDraft = State(initialValue: initialFeedbackDraft)
    }

    private var title: String {
        editingFeedback == nil ? "Continue Research" : "Edit Follow-up Plan"
    }

    private var submitLabel: String {
        editingFeedback == nil ? "Create Next Pass" : "Update Follow-up"
    }

    private var doneLabel: String {
        editingFeedback == nil ? "Back to Research" : "Done"
    }

    private var trimmedFeedbackDraft: String {
        feedbackDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var submissionRequest: ObjectiveFeedbackSubmissionRequest {
        ObjectiveFeedbackSubmissionRequest(
            content: trimmedFeedbackDraft,
            feedbackKind: selectedFeedbackKind,
            taskId: selectedFeedbackTarget.taskId,
            researchSnapshotId: selectedFeedbackTarget.researchSnapshotId,
            targetLabel: selectedFeedbackTarget.label,
            targetPreview: selectedFeedbackTarget.preview
        )
    }

    private var feedbackTargets: [ObjectiveFeedbackTarget] {
        var targets = [ObjectiveFeedbackTarget(
            id: ObjectiveFeedbackTarget.objectiveID,
            label: "Entire objective",
            preview: ObjectiveFeedbackPresentation.previewText(objectiveGoal)
        )]
        targets.append(contentsOf: snapshots.prefix(8).map {
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

    private var footerCopy: String {
        if objectiveStatus == "active" {
            return "Active objectives can queue approved follow-up work automatically so the agent can keep going."
        }
        return "Pending objectives save the next pass for later, and larger batches stay under review until you approve them."
    }

    private var submissionStateTitle: String {
        switch submissionPhase {
        case .editing:
            return title
        case .submitting:
            return editingFeedback == nil ? "Sending Feedback" : "Updating Follow-up"
        case .receivedBuildingPlan:
            return editingFeedback == nil ? "Creating Next Pass" : "Saving Follow-up"
        case .success:
            return editingFeedback == nil ? "Next Pass Ready" : "Follow-up Updated"
        case .timedOut:
            return "Still Working"
        }
    }

    private var isBlockingDismiss: Bool {
        switch submissionPhase {
        case .submitting, .receivedBuildingPlan:
            return true
        default:
            return false
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch submissionPhase {
                case .editing:
                    Form {
                        Section("Context") {
                            FeedbackComposerContextCard(
                                kind: ObjectiveFeedbackKindOption.from(rawValue: selectedFeedbackKind),
                                targetLabel: selectedFeedbackTarget.label,
                                targetPreview: selectedFeedbackTarget.preview
                            )
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
                                Task { await submit() }
                            } label: {
                                Label(submitLabel, systemImage: "arrow.triangle.branch")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ObjectiveFeedbackKindOption.from(rawValue: selectedFeedbackKind).tint)
                            .disabled(trimmedFeedbackDraft.isEmpty)
                        } header: {
                            Text("Next Pass")
                        } footer: {
                            Text(footerCopy)
                        }
                    }

                case .submitting, .receivedBuildingPlan:
                    FeedbackComposerSubmissionStateView(
                        kind: ObjectiveFeedbackKindOption.from(rawValue: selectedFeedbackKind),
                        targetLabel: selectedFeedbackTarget.label,
                        targetPreview: selectedFeedbackTarget.preview,
                        content: trimmedFeedbackDraft,
                        status: {
                            switch submissionPhase {
                            case .submitting:
                                return "submitting"
                            default:
                                return "received_building_plan"
                            }
                        }()
                    )

                case .success(let result):
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            FeedbackComposerStatusHeader(
                                title: editingFeedback == nil ? "Feedback received" : "Follow-up updated",
                                message: ObjectiveFeedbackPresentation.statusMessage(
                                    for: result.objectiveFeedback.status,
                                    objectiveStatus: objectiveStatus
                                ) ?? "The Research screen will keep this next pass connected to your feedback."
                            )

                            ObjectiveFeedbackPlanCard(
                                model: ObjectiveFeedbackCardModel(
                                    feedback: result.objectiveFeedback,
                                    targetLabel: submissionRequest.targetLabel,
                                    targetPreview: submissionRequest.targetPreview,
                                    followUpTasks: result.followUpTasks
                                ),
                                objectiveStatus: objectiveStatus,
                                isHighlighted: true
                            )

                            Button(doneLabel) {
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    }

                case .timedOut(let pendingSubmission):
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            FeedbackComposerStatusHeader(
                                title: "Feedback received",
                                message: "This request is taking longer than expected. The Research screen will keep refreshing so you can see the next pass as soon as it lands.",
                                systemImage: "clock.badge.exclamationmark.fill",
                                tint: .orange
                            )

                            ObjectiveFeedbackPlanCard(
                                model: pendingSubmission.card,
                                objectiveStatus: objectiveStatus,
                                isHighlighted: true
                            )

                            Button(doneLabel) {
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(submissionStateTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case .editing = submissionPhase {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(isBlockingDismiss)
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

        let request = submissionRequest
        let submittedAt = Date()

        errorMessage = nil
        submissionPhase = .submitting

        let acknowledgementTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            await MainActor.run {
                if case .submitting = submissionPhase {
                    submissionPhase = .receivedBuildingPlan
                }
            }
        }

        do {
            let result: IOSBackendSubmitObjectiveFeedbackResult
            if let editingFeedback {
                result = try await store.updateObjectiveFeedback(
                    objectiveId: objectiveId,
                    feedbackId: editingFeedback.id,
                    content: request.content,
                    feedbackKind: request.feedbackKind,
                    taskId: request.taskId,
                    researchSnapshotId: request.researchSnapshotId
                )
            } else {
                result = try await store.submitObjectiveFeedback(
                    id: objectiveId,
                    content: request.content,
                    feedbackKind: request.feedbackKind,
                    taskId: request.taskId,
                    researchSnapshotId: request.researchSnapshotId
                )
            }
            acknowledgementTask.cancel()
            onSubmitted?(result)
            submissionPhase = .success(result)
        } catch {
            acknowledgementTask.cancel()
            if isTimeoutError(error) {
                let pendingSubmission = ObjectiveFeedbackPendingSubmission(
                    request: request,
                    card: ObjectiveFeedbackCardModel.pending(
                        from: request,
                        status: "timed_out_but_refreshing",
                        createdAt: submittedAt
                    ),
                    submittedAt: submittedAt
                )
                onTimedOut?(pendingSubmission)
                submissionPhase = .timedOut(pendingSubmission)
            } else {
                submissionPhase = .editing
                errorMessage = error.localizedDescription
            }
        }
    }

    private func isTimeoutError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code == .timedOut
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == URLError.timedOut.rawValue
    }
}

struct ObjectiveFeedbackPlanCard: View {
    let model: ObjectiveFeedbackCardModel
    let objectiveStatus: String
    var isHighlighted = false
    var isWorking = false
    var onApprove: (() -> Void)? = nil
    var onRegenerate: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil

    @State private var taskExpansionOverride: Bool?

    private var kind: ObjectiveFeedbackKindOption {
        .from(rawValue: model.feedbackKind)
    }

    private var statusColor: Color {
        ObjectiveFeedbackPresentation.statusColor(for: model.status)
    }

    private var statusLabel: String {
        ObjectiveFeedbackPresentation.statusLabel(for: model.status)
    }

    private var defaultTasksExpanded: Bool {
        isHighlighted || model.status == "review_required" || model.status == "completed"
    }

    private var showsTasks: Bool {
        !model.followUpTasks.isEmpty && (taskExpansionOverride ?? defaultTasksExpanded)
    }

    private var approvalLabel: String {
        objectiveStatus == "active" ? "Approve & queue" : "Approve"
    }

    private var relativeDate: Date {
        model.completedAt ?? model.createdAt
    }

    private var taskDisclosureLabel: String {
        let count = model.followUpTasks.count
        let label = count == 1 ? "linked task" : "linked tasks"
        return "\(count) \(label)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

                Text(relativeDate, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(model.targetLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let targetPreview = ObjectiveFeedbackPresentation.previewText(model.targetPreview) {
                    Text(targetPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(model.content)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let statusMessage = ObjectiveFeedbackPresentation.statusMessage(for: model.status, objectiveStatus: objectiveStatus) {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !model.followUpTasks.isEmpty {
                Button {
                    taskExpansionOverride = !(taskExpansionOverride ?? defaultTasksExpanded)
                } label: {
                    HStack(spacing: 8) {
                        Text(taskDisclosureLabel)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Image(systemName: showsTasks ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if showsTasks {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.followUpTasks) { task in
                            TaskRow(task: task)
                        }
                    }
                    .padding(10)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            if let completionSummary = model.completionSummary, !completionSummary.isEmpty {
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

            if model.status == "review_required" {
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
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isHighlighted ? statusColor.opacity(0.45) : Color.clear, lineWidth: 2)
        }
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

private struct FeedbackComposerContextCard: View {
    let kind: ObjectiveFeedbackKindOption
    let targetLabel: String
    let targetPreview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(kind.label, systemImage: kind.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(kind.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(kind.tint.opacity(0.14))
                    .clipShape(Capsule())

                Text("Focused on \(targetLabel)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let targetPreview = ObjectiveFeedbackPresentation.previewText(targetPreview) {
                Text(targetPreview)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct FeedbackComposerSubmissionStateView: View {
    let kind: ObjectiveFeedbackKindOption
    let targetLabel: String
    let targetPreview: String?
    let content: String
    let status: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FeedbackComposerStatusHeader(
                    title: status == "submitting" ? "Sending your feedback" : "Feedback received",
                    message: ObjectiveFeedbackPresentation.statusMessage(for: status, objectiveStatus: "active")
                        ?? "Building the next pass now.",
                    systemImage: status == "submitting" ? "arrow.up.circle.fill" : "arrow.triangle.branch.circle.fill",
                    tint: status == "submitting" ? .blue : .teal,
                    showsProgress: true
                )

                ObjectiveFeedbackPlanCard(
                    model: ObjectiveFeedbackCardModel(
                        id: "composer-\(status)",
                        feedbackId: nil,
                        feedbackKind: kind.rawValue,
                        status: status,
                        content: content,
                        createdAt: Date(),
                        targetLabel: targetLabel,
                        targetPreview: targetPreview,
                        followUpTasks: []
                    ),
                    objectiveStatus: "active",
                    isHighlighted: true
                )
            }
            .padding()
        }
    }
}

private struct FeedbackComposerStatusHeader: View {
    let title: String
    let message: String
    var systemImage = "checkmark.circle.fill"
    var tint: Color = .green
    var showsProgress = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                if showsProgress {
                    ProgressView()
                }
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
    @State private var pendingFeedbackSubmission: ObjectiveFeedbackPendingSubmission?
    @State private var feedbackErrorMessage: String?
    @State private var activeFeedbackActionID: UUID?
    @State private var activityDetail: IOSBackendObjectiveDetail?
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

    private var activityFeedbacks: [IOSBackendObjectiveFeedback] {
        activityDetail?.objectiveFeedbacks ?? []
    }

    private var sortedActivityFeedbacks: [IOSBackendObjectiveFeedback] {
        activityFeedbacks.sorted { $0.createdAt > $1.createdAt }
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

    private var latestTrackedFeedbackId: UUID? {
        latestFollowUpCard?.feedbackId
    }

    private var latestTrackedQueuedTaskCount: Int {
        guard let feedbackId = latestTrackedFeedbackId else { return 0 }
        return activityTasks.filter { $0.sourceFeedbackId == feedbackId && $0.status == "pending" }.count
    }

    private var latestTrackedRunningTaskCount: Int {
        guard let feedbackId = latestTrackedFeedbackId else { return 0 }
        return activityTasks.filter { $0.sourceFeedbackId == feedbackId && $0.status == "in_progress" }.count
    }

    private var followUpLoopCards: [ObjectiveFeedbackCardModel] {
        var cards: [ObjectiveFeedbackCardModel] = []

        if let pendingFeedbackSubmission {
            cards.append(pendingFeedbackSubmission.card)
        }

        if let latestFeedbackResult,
           !sortedActivityFeedbacks.contains(where: { $0.id == latestFeedbackResult.objectiveFeedback.id }) {
            cards.append(
                feedbackCardModel(
                    for: latestFeedbackResult.objectiveFeedback,
                    linkedTasks: latestFeedbackResult.followUpTasks
                )
            )
        }

        for feedback in sortedActivityFeedbacks {
            let alreadyPresent = cards.contains { card in
                card.feedbackId == feedback.id
            }
            if !alreadyPresent {
                cards.append(feedbackCardModel(for: feedback))
            }
        }

        return cards
    }

    private var latestFollowUpCard: ObjectiveFeedbackCardModel? {
        followUpLoopCards.first
    }

    private var historicalFollowUpCards: [ObjectiveFeedbackCardModel] {
        Array(followUpLoopCards.dropFirst())
    }

    private var shouldShowAgentActivity: Bool {
        latestFollowUpCard != nil ||
            pendingFeedbackSubmission != nil ||
            runningTaskCount > 0 ||
            queuedTaskCount > 0 ||
            onlineAgentsCount > 0
    }

    private var shouldPollAgentActivity: Bool {
        pendingFeedbackSubmission != nil ||
            runningTaskCount > 0 ||
            queuedTaskCount > 0 ||
            (activityPollUntil.map { $0 > Date() } ?? false)
    }

    private var agentActivityMessage: String {
        if pendingFeedbackSubmission != nil {
            return "Still working on your latest follow-up. This screen will keep refreshing until the next pass shows up."
        }
        if latestTrackedRunningTaskCount > 0 {
            if latestTrackedRunningTaskCount == 1 {
                return "Work from your latest follow-up is now running."
            }
            return "\(latestTrackedRunningTaskCount) tasks from your latest follow-up are now running."
        }
        if latestTrackedQueuedTaskCount > 0 {
            if onlineAgentsCount > 0 {
                if latestTrackedQueuedTaskCount == 1 {
                    return "Your latest follow-up is queued for the next available agent."
                }
                return "\(latestTrackedQueuedTaskCount) tasks from your latest follow-up are queued for the next available agent."
            }
            if latestTrackedQueuedTaskCount == 1 {
                return "Your latest follow-up is queued, but no agent looks online yet."
            }
            return "\(latestTrackedQueuedTaskCount) tasks from your latest follow-up are queued, but no agent looks online yet."
        }
        if let latestFollowUpCard,
           let statusMessage = ObjectiveFeedbackPresentation.statusMessage(for: latestFollowUpCard.status, objectiveStatus: objectiveStatus) {
            return statusMessage
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

                        if let latestFollowUpCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Latest Follow-up")
                                    .font(.headline)
                                followUpCard(for: latestFollowUpCard)
                            }
                        }

                        if shouldShowAgentActivity {
                            ResearchAgentActivityCard(
                                runningTaskCount: runningTaskCount,
                                queuedTaskCount: queuedTaskCount,
                                onlineAgentsCount: onlineAgentsCount,
                                message: agentActivityMessage,
                                showsProgress: pendingFeedbackSubmission != nil
                            )
                        }

                        if !historicalFollowUpCards.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Follow-up Loop")
                                    .font(.headline)
                                ForEach(historicalFollowUpCards) { card in
                                    followUpCard(for: card)
                                }
                            }
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
                    if let latestFollowUpCard {
                        Section("Latest Follow-up") {
                            followUpCard(for: latestFollowUpCard)
                                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                .listRowBackground(Color.clear)
                        }
                    }

                    if shouldShowAgentActivity {
                        Section("Agent Activity") {
                            ResearchAgentActivityCard(
                                runningTaskCount: runningTaskCount,
                                queuedTaskCount: queuedTaskCount,
                                onlineAgentsCount: onlineAgentsCount,
                                message: agentActivityMessage,
                                showsProgress: pendingFeedbackSubmission != nil
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                        }
                    }

                    if !historicalFollowUpCards.isEmpty {
                        Section("Follow-up Loop") {
                            ForEach(historicalFollowUpCards) { card in
                                followUpCard(for: card)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                    .listRowBackground(Color.clear)
                            }
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
                    handleFeedbackSubmitted(result)
                },
                onTimedOut: { pending in
                    handleFeedbackTimedOut(pending)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
            return ObjectiveFeedbackPresentation.targetLabel(for: snapshot)
        }
        if let taskId = feedback.taskId,
           let task = activityTasks.first(where: { $0.id == taskId }) ?? tasks.first(where: { $0.id == taskId }) {
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
           let task = activityTasks.first(where: { $0.id == taskId }) ?? tasks.first(where: { $0.id == taskId }) {
            return ObjectiveFeedbackPresentation.previewText(task.description)
        }
        return ObjectiveFeedbackPresentation.previewText(objectiveGoal)
    }

    private func followUpTasks(for feedback: IOSBackendObjectiveFeedback) -> [IOSBackendTask] {
        activityTasks.filter { $0.sourceFeedbackId == feedback.id }
    }

    private func feedbackRecord(for feedbackId: UUID?) -> IOSBackendObjectiveFeedback? {
        guard let feedbackId else { return nil }
        if let feedback = activityFeedbacks.first(where: { $0.id == feedbackId }) {
            return feedback
        }
        if latestFeedbackResult?.objectiveFeedback.id == feedbackId {
            return latestFeedbackResult?.objectiveFeedback
        }
        return nil
    }

    private func feedbackCardModel(
        for feedback: IOSBackendObjectiveFeedback,
        linkedTasks: [IOSBackendTask]? = nil
    ) -> ObjectiveFeedbackCardModel {
        ObjectiveFeedbackCardModel(
            feedback: feedback,
            targetLabel: feedbackTargetLabel(for: feedback),
            targetPreview: feedbackTargetPreview(for: feedback),
            followUpTasks: linkedTasks ?? followUpTasks(for: feedback)
        )
    }

    @ViewBuilder
    private func followUpCard(for model: ObjectiveFeedbackCardModel) -> some View {
        let feedback = feedbackRecord(for: model.feedbackId)
        let requiresReview = feedback?.status == "review_required"

        ObjectiveFeedbackPlanCard(
            model: model,
            objectiveStatus: objectiveStatus,
            isHighlighted: latestFollowUpCard?.id == model.id,
            isWorking: feedback?.id == activeFeedbackActionID,
            onApprove: requiresReview ? {
                if let feedback {
                    Task { await approveFeedbackPlan(feedback) }
                }
            } : nil,
            onRegenerate: requiresReview ? {
                if let feedback {
                    Task { await regenerateFeedbackPlan(feedback) }
                }
            } : nil,
            onEdit: requiresReview ? {
                if let feedback {
                    composerContext = composerContext(for: feedback)
                }
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

    @MainActor
    private func handleFeedbackSubmitted(_ result: IOSBackendSubmitObjectiveFeedbackResult) {
        pendingFeedbackSubmission = nil
        latestFeedbackResult = result
        onFeedbackMutated?()
        extendActivityPolling()
        reconcileActivityPolling()

        Task {
            await refreshActivityStatus()
            extendActivityPolling()
            reconcileActivityPolling()
        }
    }

    @MainActor
    private func handleFeedbackTimedOut(_ pending: ObjectiveFeedbackPendingSubmission) {
        pendingFeedbackSubmission = pending
        extendActivityPolling()
        reconcileActivityPolling()

        Task {
            await refreshActivityStatus()
        }
    }

    @MainActor
    private func approveFeedbackPlan(_ feedback: IOSBackendObjectiveFeedback) async {
        feedbackErrorMessage = nil
        activeFeedbackActionID = feedback.id
        defer { activeFeedbackActionID = nil }

        do {
            let result = try await store.approveObjectiveFeedbackPlan(objectiveId: objectiveId, feedbackId: feedback.id)
            latestFeedbackResult = result
            pendingFeedbackSubmission = nil
            onFeedbackMutated?()
            await refreshActivityStatus()
            extendActivityPolling()
            reconcileActivityPolling()
        } catch {
            feedbackErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func regenerateFeedbackPlan(_ feedback: IOSBackendObjectiveFeedback) async {
        feedbackErrorMessage = nil
        activeFeedbackActionID = feedback.id
        defer { activeFeedbackActionID = nil }

        do {
            let result = try await store.regenerateObjectiveFeedbackPlan(objectiveId: objectiveId, feedbackId: feedback.id)
            latestFeedbackResult = result
            pendingFeedbackSubmission = nil
            onFeedbackMutated?()
            await refreshActivityStatus()
            extendActivityPolling()
            reconcileActivityPolling()
        } catch {
            feedbackErrorMessage = error.localizedDescription
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
            let detail = try await store.fetchDetail(for: objectiveId)
            activityDetail = detail
            reconcileFeedbackState(with: detail)
        } catch {
            IOSRuntimeLog.log("[GenerativeResultsView] Activity refresh failed: \(error)")
        }
    }

    @MainActor
    private func reconcileFeedbackState(with detail: IOSBackendObjectiveDetail) {
        if let latestFeedbackId = latestFeedbackResult?.objectiveFeedback.id,
           let feedback = detail.objectiveFeedbacks.first(where: { $0.id == latestFeedbackId }) {
            latestFeedbackResult = IOSBackendSubmitObjectiveFeedbackResult(
                objective: detail.objective,
                objectiveFeedback: feedback,
                followUpTasks: detail.tasks.filter { $0.sourceFeedbackId == feedback.id }
            )
        }

        if let pendingFeedbackSubmission,
           let feedback = detail.objectiveFeedbacks.first(where: { matchesPendingSubmission($0, pending: pendingFeedbackSubmission) }) {
            latestFeedbackResult = IOSBackendSubmitObjectiveFeedbackResult(
                objective: detail.objective,
                objectiveFeedback: feedback,
                followUpTasks: detail.tasks.filter { $0.sourceFeedbackId == feedback.id }
            )
            self.pendingFeedbackSubmission = nil
        }
    }

    private func matchesPendingSubmission(
        _ feedback: IOSBackendObjectiveFeedback,
        pending: ObjectiveFeedbackPendingSubmission
    ) -> Bool {
        feedback.content == pending.request.content &&
            feedback.feedbackKind == pending.request.feedbackKind &&
            feedback.taskId == pending.request.taskId &&
            feedback.researchSnapshotId == pending.request.researchSnapshotId &&
            feedback.createdAt >= pending.submittedAt.addingTimeInterval(-15)
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
