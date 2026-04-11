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
        onSubmitted: ((IOSBackendSubmitObjectiveFeedbackResult) -> Void)? = nil
    ) {
        self.objectiveId = objectiveId
        self.objectiveGoal = objectiveGoal
        self.objectiveStatus = objectiveStatus
        self.tasks = tasks
        self.snapshots = snapshots
        self.editingFeedback = editingFeedback
        self.onSubmitted = onSubmitted
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
                        Task { await submit() }
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
                    content: trimmedFeedbackDraft,
                    feedbackKind: selectedFeedbackKind,
                    taskId: selectedFeedbackTarget.taskId,
                    researchSnapshotId: selectedFeedbackTarget.researchSnapshotId
                )
            } else {
                result = try await store.submitObjectiveFeedback(
                    id: objectiveId,
                    content: trimmedFeedbackDraft,
                    feedbackKind: selectedFeedbackKind,
                    taskId: selectedFeedbackTarget.taskId,
                    researchSnapshotId: selectedFeedbackTarget.researchSnapshotId
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

                HStack(spacing: 8) {
                    if let onApprove {
                        Button {
                            onApprove()
                        } label: {
                            Label(approvalLabel, systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }

                    if let onRegenerate {
                        Button {
                            onRegenerate()
                        } label: {
                            Label("Regenerate", systemImage: "arrow.trianglehead.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }

                    if let onEdit {
                        Button {
                            onEdit()
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .buttonStyle(.bordered)
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

    private var canContinueResearch: Bool {
        objectiveStatus == "pending" || objectiveStatus == "active"
    }

    private var quickFeedbackKinds: [ObjectiveFeedbackKindOption] {
        [.followUp, .compareOptions, .challengeResult]
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

                        if let latestFeedbackResult {
                            ObjectiveFeedbackPlanCard(
                                feedback: latestFeedbackResult.objectiveFeedback,
                                targetLabel: feedbackTargetLabel(for: latestFeedbackResult.objectiveFeedback),
                                objectiveStatus: objectiveStatus,
                                followUpTasks: latestFeedbackResult.followUpTasks,
                                isHighlighted: true,
                                isWorking: activeFeedbackAction != nil,
                                onApprove: latestFeedbackResult.objectiveFeedback.status == "review_required" ? {
                                    Task { await approveLatestFeedbackPlan() }
                                } : nil,
                                onRegenerate: latestFeedbackResult.objectiveFeedback.status == "review_required" ? {
                                    Task { await regenerateLatestFeedbackPlan() }
                                } : nil,
                                onEdit: latestFeedbackResult.objectiveFeedback.status == "review_required" ? {
                                    composerContext = composerContext(for: latestFeedbackResult.objectiveFeedback)
                                } : nil
                            )
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
                    if let latestFeedbackResult {
                        Section("Latest Follow-up Plan") {
                            ObjectiveFeedbackPlanCard(
                                feedback: latestFeedbackResult.objectiveFeedback,
                                targetLabel: feedbackTargetLabel(for: latestFeedbackResult.objectiveFeedback),
                                objectiveStatus: objectiveStatus,
                                followUpTasks: latestFeedbackResult.followUpTasks,
                                isHighlighted: true,
                                isWorking: activeFeedbackAction != nil,
                                onApprove: latestFeedbackResult.objectiveFeedback.status == "review_required" ? {
                                    Task { await approveLatestFeedbackPlan() }
                                } : nil,
                                onRegenerate: latestFeedbackResult.objectiveFeedback.status == "review_required" ? {
                                    Task { await regenerateLatestFeedbackPlan() }
                                } : nil,
                                onEdit: latestFeedbackResult.objectiveFeedback.status == "review_required" ? {
                                    composerContext = composerContext(for: latestFeedbackResult.objectiveFeedback)
                                } : nil
                            )
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
                        Task { await loadPresentation() }
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
        .task { await loadPresentation() }
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
}
