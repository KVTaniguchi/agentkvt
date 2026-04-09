import SwiftUI

private enum ObjectiveComposerStage {
    case archetypes
    case drafting
    case review
}

private enum ObjectiveComposerTemplate: String, CaseIterable, Identifiable {
    case generic
    case budget
    case dateNight = "date_night"
    case tripPlanning = "trip_planning"
    case householdPlanning = "household_planning"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generic: return "Custom Objective"
        case .budget: return "Budget"
        case .dateNight: return "Date Night"
        case .tripPlanning: return "Trip Planning"
        case .householdPlanning: return "Household Planning"
        }
    }

    var subtitle: String {
        switch self {
        case .generic:
            return "Start from a rough goal and let the server ask clarifying questions."
        case .budget:
            return "Shape a budget objective around targets, limits, and the output you want."
        case .dateNight:
            return "Capture budget, timing, vibe, and location before the planner starts researching."
        case .tripPlanning:
            return "Turn a destination idea into a planning-ready travel brief."
        case .householdPlanning:
            return "Clarify chores, projects, deadlines, and constraints for home planning."
        }
    }

    var iconName: String {
        switch self {
        case .generic: return "sparkles"
        case .budget: return "chart.pie"
        case .dateNight: return "heart.text.square"
        case .tripPlanning: return "airplane"
        case .householdPlanning: return "house"
        }
    }
}

struct ObjectiveComposerView: View {
    @Environment(ObjectiveDraftStore.self) private var draftStore
    @Environment(ObjectivesStore.self) private var objectivesStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileStore: FamilyProfileStore

    @State private var stage: ObjectiveComposerStage = .archetypes
    @State private var selectedTemplate: ObjectiveComposerTemplate?
    @State private var draftedMessage = ""
    @State private var reviewGoal = ""
    @State private var startImmediately = true
    @State private var showingLegacyFallback = false
    @State private var localErrorMessage: String?

    private var draft: IOSBackendObjectiveDraft? {
        draftStore.activeDraft
    }

    private var navigationTitle: String {
        if showingLegacyFallback { return "New Objective" }
        switch stage {
        case .archetypes:
            return "New Objective"
        case .drafting:
            return selectedTemplate?.title ?? "Objective Composer"
        case .review:
            return "Review Objective"
        }
    }

    private var canReview: Bool {
        draft?.readyToFinalize == true
    }

    var body: some View {
        NavigationStack {
            Group {
                if showingLegacyFallback {
                    LegacyObjectiveCreateView(
                        fallbackMessage: "Guided drafting is not available on this server yet. You can still create a standard objective below."
                    ) {
                        draftStore.reset()
                        dismiss()
                    }
                } else {
                    switch stage {
                    case .archetypes:
                        archetypePicker
                    case .drafting:
                        draftingView
                    case .review:
                        reviewView
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(leadingButtonTitle) {
                        handleLeadingAction()
                    }
                }
                if stage == .drafting && !showingLegacyFallback {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Review") {
                            prepareReview()
                        }
                        .disabled(!canReview)
                    }
                }
            }
        }
        .task {
            await resumeIfNeeded()
        }
        .alert("Objective Composer", isPresented: Binding(
            get: { localErrorMessage != nil },
            set: { if !$0 { localErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { localErrorMessage = nil }
        } message: {
            Text(localErrorMessage ?? "Something went wrong.")
        }
    }

    private var leadingButtonTitle: String {
        if showingLegacyFallback || stage == .archetypes {
            return "Cancel"
        }
        return "Back"
    }

    private var archetypePicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pick a starting point")
                    .font(.headline)
                    .padding(.top, 8)

                ForEach(ObjectiveComposerTemplate.allCases) { template in
                    Button {
                        Task { await beginDraft(for: template) }
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: template.iconName)
                                .font(.title3)
                                .frame(width: 28, height: 28)
                                .foregroundStyle(Color.accentColor)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(template.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(template.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()
                        }
                        .padding(16)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(draftStore.isStarting)
                }

                if draftStore.isStarting {
                    ProgressView("Starting guided draft...")
                        .padding(.top, 8)
                }
            }
            .padding()
        }
    }

    private var draftingView: some View {
        VStack(spacing: 0) {
            if let draft {
                ObjectiveDraftSummaryCard(draft: draft)
                    .padding([.horizontal, .top])
            }

            if let draft {
                ScrollViewReader { proxy in
                    List {
                        ForEach(draft.messages) { message in
                            ObjectiveComposerMessageRow(message: message)
                                .id(message.id)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .onAppear {
                        scrollToLatest(proxy: proxy, messages: draft.messages)
                    }
                    .onChange(of: draft.messages.map(\.id)) { _, _ in
                        scrollToLatest(proxy: proxy, messages: draft.messages)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Start A Draft",
                    systemImage: "wand.and.stars",
                    description: Text("Choose an archetype to begin guided objective drafting.")
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                if canReview {
                    Label("This draft is ready to review.", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Reply to the planner", text: $draftedMessage, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)

                    Button("Send") {
                        Task { await sendDraftMessage() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        draftedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        draftStore.isSending ||
                        draftStore.activeDraft == nil
                    )
                }
            }
            .padding()
            .background(.thinMaterial)
        }
    }

    private var reviewView: some View {
        Form {
            Section("Goal") {
                TextField("Objective goal", text: $reviewGoal, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section("Planner Summary") {
                Text(plannerSummary)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.primary)
            }

            Section {
                Toggle("Start immediately (Active)", isOn: $startImmediately)
            } footer: {
                Text("Active objectives trigger the Mac agent to decompose tasks automatically.")
            }

            if let draft, !draft.missingFields.isEmpty {
                Section("Still Missing") {
                    ForEach(draft.missingFields, id: \.self) { field in
                        Text(ObjectiveDraftSummaryCard.humanizedField(field))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await finalizeDraft() }
            } label: {
                if draftStore.isFinalizing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Create Objective")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .disabled(
                reviewGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                draftStore.isFinalizing
            )
            .background(.thinMaterial)
        }
    }

    private var plannerSummary: String {
        IOSObjectivePlannerSummaryBuilder.summary(
            goal: reviewGoal,
            templateKey: selectedTemplate?.rawValue ?? draft?.templateKey,
            brief: draft?.briefJson ?? .init()
        )
    }

    @MainActor
    private func beginDraft(for template: ObjectiveComposerTemplate) async {
        do {
            _ = try await draftStore.startDraft(
                templateKey: template.rawValue,
                createdByProfileId: profileStore.currentProfileId
            )
            selectedTemplate = template
            stage = .drafting
        } catch ObjectiveDraftStoreError.composerUnavailable {
            showingLegacyFallback = true
        } catch {
            localErrorMessage = error.localizedDescription
            IOSRuntimeLog.log("[ObjectiveComposerView] start draft failed: \(error)")
        }
    }

    @MainActor
    private func sendDraftMessage() async {
        do {
            _ = try await draftStore.sendMessage(draftedMessage)
            draftedMessage = ""
        } catch {
            localErrorMessage = error.localizedDescription
            IOSRuntimeLog.log("[ObjectiveComposerView] send draft message failed: \(error)")
        }
    }

    @MainActor
    private func finalizeDraft() async {
        do {
            let finalized = try await draftStore.finalizeDraft(
                goal: reviewGoal,
                briefJson: draft?.briefJson ?? .init(),
                startImmediately: startImmediately
            )
            objectivesStore.upsertObjective(finalized)
            draftStore.reset()
            dismiss()
        } catch {
            localErrorMessage = error.localizedDescription
            IOSRuntimeLog.log("[ObjectiveComposerView] finalize draft failed: \(error)")
        }
    }

    @MainActor
    private func prepareReview() {
        reviewGoal = draft?.suggestedGoal ?? draft?.plannerSummary ?? ""
        stage = .review
    }

    @MainActor
    private func handleLeadingAction() {
        if showingLegacyFallback || stage == .archetypes {
            draftStore.reset()
            dismiss()
            return
        }

        switch stage {
        case .review:
            stage = .drafting
        case .drafting:
            stage = .archetypes
            draftStore.reset()
            selectedTemplate = nil
        case .archetypes:
            dismiss()
        }
    }

    @MainActor
    private func resumeIfNeeded() async {
        await draftStore.resumePersistedDraftIfNeeded()
        guard !showingLegacyFallback else { return }
        guard let draft = draftStore.activeDraft, draft.status == "drafting" else { return }
        selectedTemplate = ObjectiveComposerTemplate(rawValue: draft.templateKey)
        stage = .drafting
    }

    private func scrollToLatest(proxy: ScrollViewProxy, messages: [IOSBackendObjectiveDraftMessage]) {
        guard let lastID = messages.last?.id else { return }
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}

private struct ObjectiveDraftSummaryCard: View {
    let draft: IOSBackendObjectiveDraft

    static func humanizedField(_ field: String) -> String {
        field
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What AgentKVT Understands")
                .font(.headline)

            if let suggestedGoal = draft.suggestedGoal, !suggestedGoal.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suggested Goal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(suggestedGoal)
                        .font(.subheadline)
                }
            }

            ObjectiveBriefSection(title: "Context", items: draft.briefJson.context)
            ObjectiveBriefSection(title: "Success Criteria", items: draft.briefJson.successCriteria)
            ObjectiveBriefSection(title: "Constraints", items: draft.briefJson.constraints)
            ObjectiveBriefSection(title: "Preferences", items: draft.briefJson.preferences)

            if let deliverable = draft.briefJson.deliverable, !deliverable.isEmpty {
                ObjectiveBriefSection(title: "Deliverable", items: [deliverable])
            }

            if !draft.missingFields.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Still Missing")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(draft.missingFields.map(Self.humanizedField).joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ObjectiveBriefSection: View {
    let title: String
    let items: [String]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(items, id: \.self) { item in
                    Text("- \(item)")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

private struct ObjectiveComposerMessageRow: View {
    let message: IOSBackendObjectiveDraftMessage

    private var isUser: Bool {
        message.role == "user"
    }

    private var bubbleColor: Color {
        isUser ? .blue : Color(.secondarySystemBackground)
    }

    private var textColor: Color {
        isUser ? .white : .primary
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 28) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(isUser ? "You" : "Planner")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(message.content)
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleColor)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .textSelection(.enabled)
            }

            if !isUser { Spacer(minLength: 28) }
        }
    }
}

private struct LegacyObjectiveCreateView: View {
    @Environment(ObjectivesStore.self) private var store

    let fallbackMessage: String?
    let onComplete: () -> Void

    @State private var goal = ""
    @State private var launchActive = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let fallbackMessage {
                Section {
                    Text(fallbackMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Goal") {
                TextField("e.g. San Diego trip logistics", text: $goal, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                Toggle("Start immediately (Active)", isOn: $launchActive)
            } footer: {
                Text("Active objectives trigger the Mac agent to decompose tasks automatically.")
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save Objective")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .alert("Could Not Create Objective", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An error occurred.")
        }
    }

    @MainActor
    private func save() async {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await store.createObjective(goal: trimmed, status: launchActive ? "active" : "pending")
            onComplete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum IOSObjectivePlannerSummaryBuilder {
    static func summary(
        goal: String,
        templateKey: String?,
        brief: IOSBackendObjectiveBrief
    ) -> String {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []

        if !trimmedGoal.isEmpty {
            lines.append("Goal: \(trimmedGoal)")
        }

        if let templateKey, let template = ObjectiveComposerTemplate(rawValue: templateKey) {
            lines.append("Objective archetype: \(template.title)")
        }

        appendSection("Context", items: brief.context, to: &lines)
        appendSection("Success criteria", items: brief.successCriteria, to: &lines)
        appendSection("Constraints", items: brief.constraints, to: &lines)
        appendSection("Preferences", items: brief.preferences, to: &lines)

        if let deliverable = brief.deliverable, !deliverable.isEmpty {
            lines.append("Deliverable:")
            lines.append("- \(deliverable)")
        }

        appendSection("Open questions", items: brief.openQuestions, to: &lines)

        return lines.joined(separator: "\n")
    }

    private static func appendSection(_ title: String, items: [String], to lines: inout [String]) {
        guard !items.isEmpty else { return }
        lines.append("\(title):")
        items.forEach { lines.append("- \($0)") }
    }
}
