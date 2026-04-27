import SwiftUI
import PhotosUI

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
    case restaurantReservation = "restaurant_reservation"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generic: return "Custom Objective"
        case .budget: return "Budget"
        case .dateNight: return "Date Night"
        case .tripPlanning: return "Trip Planning"
        case .householdPlanning: return "Household Planning"
        case .restaurantReservation: return "Restaurant Reservation"
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
        case .restaurantReservation:
            return "Find and book a restaurant — the agent surfaces options and waits for your pick before reserving."
        }
    }

    var iconName: String {
        switch self {
        case .generic: return "sparkles"
        case .budget: return "chart.pie"
        case .dateNight: return "heart.text.square"
        case .tripPlanning: return "airplane"
        case .householdPlanning: return "house"
        case .restaurantReservation: return "fork.knife"
        }
    }
}

private struct PendingObjectiveComposerTurn {
    let userMessageID = UUID()
    let thinkingMessageID = UUID()
    let content: String
}

private enum ObjectiveComposerTimelineItem: Identifiable {
    case message(IOSBackendObjectiveDraftMessage)
    case pendingUser(id: UUID, content: String)
    case thinking(id: UUID)

    var id: UUID {
        switch self {
        case .message(let message):
            return message.id
        case .pendingUser(let id, _):
            return id
        case .thinking(let id):
            return id
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
    @State private var pendingTurn: PendingObjectiveComposerTurn?
    @State private var isSummarySheetPresented = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var attachedFileIds: [UUID] = []
    @State private var isUploadingPhotos = false
    @FocusState private var isDraftMessageFieldFocused: Bool

    private var draft: IOSBackendObjectiveDraft? {
        draftStore.activeDraft
    }

    private var timelineItems: [ObjectiveComposerTimelineItem] {
        var items = (draft?.messages ?? []).map(ObjectiveComposerTimelineItem.message)
        if let pendingTurn {
            items.append(.pendingUser(id: pendingTurn.userMessageID, content: pendingTurn.content))
            items.append(.thinking(id: pendingTurn.thinkingMessageID))
        }
        return items
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
                        fallbackMessage: "Guided drafting is not available on this server right now. You can still create a standard objective below, or restart the Rails API on the server to re-enable the interactive composer."
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
            }
        }
        .task {
            await resumeIfNeeded()
        }
        .sheet(isPresented: $isSummarySheetPresented) {
            if let draft {
                ObjectiveDraftSummarySheet(draft: draft)
            }
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

                ObjectiveCreationGuideCard()

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
                ObjectiveDraftStatusBar(
                    draft: draft,
                    onShowDetails: {
                        isSummarySheetPresented = true
                    }
                )
                    .padding([.horizontal, .top])
            }

            if draft != nil {
                ScrollViewReader { proxy in
                    List {
                        ForEach(timelineItems) { item in
                            ObjectiveComposerTimelineRow(item: item)
                                .id(item.id)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear {
                        scrollToLatest(proxy: proxy, items: timelineItems)
                    }
                    .onChange(of: timelineItems.map(\.id)) { _, _ in
                        scrollToLatest(proxy: proxy, items: timelineItems)
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
                if !isDraftMessageFieldFocused {
                    Text("Reply in plain language. AgentKVT keeps the brief updated as you go, and you can inspect the full summary anytime.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if draftStore.isSending {
                    Label("Planner is thinking. This can take a bit when the server model is busy.", systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if canReview {
                    Button {
                        isDraftMessageFieldFocused = false
                        prepareReview()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.body)

                            Text("Review Objective")
                                .font(.headline)

                            Spacer()

                            Image(systemName: "arrow.right")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Reply to the planner", text: $draftedMessage, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                        .focused($isDraftMessageFieldFocused)

                    Button("Send") {
                        Task { await sendDraftMessage() }
                    }
                    .buttonStyle(.borderedProminent)
                    .overlay {
                        if draftStore.isSending {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .opacity(draftStore.isSending ? 0.85 : 1)
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
            Section {
                TextField("Objective goal", text: $reviewGoal, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("Goal")
            } footer: {
                Text("This is the final title shown in your objectives list. Keep it short and outcome-focused.")
            }

            Section {
                Text(plannerSummary)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.primary)
            } header: {
                Text("Planner Summary")
            } footer: {
                Text("This is the exact structured summary the server planner will use to decompose work after you create the objective.")
            }

            Section {
                Toggle("Start immediately (Active)", isOn: $startImmediately)
            } footer: {
                Text("Active objectives are created and then immediately sent to the Mac agent for planning.")
            }

            Section {
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 3,
                    matching: .images
                ) {
                    Label(
                        attachedFileIds.isEmpty ? "Add Photos" : "\(attachedFileIds.count) Photo\(attachedFileIds.count == 1 ? "" : "s") Attached",
                        systemImage: attachedFileIds.isEmpty ? "photo.badge.plus" : "photo.stack"
                    )
                }
                .onChange(of: selectedPhotoItems) { _, newItems in
                    Task { await uploadSelectedPhotos(newItems) }
                }

                if isUploadingPhotos {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Uploading photos…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Photos")
            } footer: {
                Text("Photos give the planner visual context. Up to 3 images.")
            }

            if let draft, !draft.missingFields.isEmpty {
                Section("Still Missing") {
                    ForEach(draft.missingFields, id: \.self) { field in
                        Text(ObjectiveComposerFieldPresentation.humanizedField(field))
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
        pendingTurn = nil
        isSummarySheetPresented = false
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
        let trimmed = draftedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isDraftMessageFieldFocused = false
        draftedMessage = ""
        pendingTurn = PendingObjectiveComposerTurn(content: trimmed)

        do {
            _ = try await draftStore.sendMessage(trimmed)
            pendingTurn = nil
        } catch {
            draftedMessage = trimmed
            pendingTurn = nil
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
                startImmediately: startImmediately,
                inboundFileIds: attachedFileIds
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
    private func uploadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isUploadingPhotos = true
        attachedFileIds = []
        defer { isUploadingPhotos = false }

        let sync = IOSBackendSyncService()
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let contentType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let fileName = "photo_\(UUID().uuidString).\(ext)"
                let uploaded = try await sync.createInboundFileRemote(
                    fileName: fileName,
                    contentType: contentType,
                    fileData: data,
                    uploadedByProfileId: nil
                )
                attachedFileIds.append(uploaded.id)
            } catch {
                IOSRuntimeLog.log("[ObjectiveComposerView] photo upload failed: \(error)")
            }
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
            pendingTurn = nil
            isSummarySheetPresented = false
            draftStore.reset()
            dismiss()
            return
        }

        switch stage {
        case .review:
            stage = .drafting
        case .drafting:
            stage = .archetypes
            pendingTurn = nil
            isSummarySheetPresented = false
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
        pendingTurn = nil
        isSummarySheetPresented = false
        selectedTemplate = ObjectiveComposerTemplate(rawValue: draft.templateKey)
        stage = .drafting
    }

    private func scrollToLatest(proxy: ScrollViewProxy, items: [ObjectiveComposerTimelineItem]) {
        guard let lastID = items.last?.id else { return }
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}

private struct ObjectiveDraftStatusBar: View {
    let draft: IOSBackendObjectiveDraft
    let onShowDetails: () -> Void

    private var capturedFieldsLabel: String {
        let count = draft.briefJson.filledFieldCount
        return "\(count) section\(count == 1 ? "" : "s") captured"
    }

    private var statusSummary: String {
        if draft.readyToFinalize {
            return "Brief looks ready. Review the goal and create the objective when it feels right."
        }

        guard !draft.missingFields.isEmpty else {
            return capturedFieldsLabel
        }

        let preview = draft.missingFields
            .prefix(2)
            .map(ObjectiveComposerFieldPresentation.humanizedField)
            .joined(separator: ", ")
        let extraCount = max(0, draft.missingFields.count - 2)
        let suffix = extraCount > 0 ? " + \(extraCount) more" : ""
        return "\(capturedFieldsLabel) • Missing \(preview)\(suffix)"
    }

    var body: some View {
        Button(action: onShowDetails) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: draft.readyToFinalize ? "checkmark.seal.fill" : "list.bullet.clipboard")
                    .font(.headline)
                    .foregroundStyle(draft.readyToFinalize ? .green : .accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Objective Brief")
                            .font(.subheadline.weight(.semibold))

                        if draft.readyToFinalize {
                            Text("Ready")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.14))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }

                    Text(statusSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("View")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)

                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ObjectiveDraftSummarySheet: View {
    @Environment(\.dismiss) private var dismiss

    let draft: IOSBackendObjectiveDraft

    private var readinessCopy: String {
        if draft.readyToFinalize {
            return "This brief already has enough detail to review and create the objective."
        }

        let missingCount = draft.missingFields.count
        return "\(draft.briefJson.filledFieldCount) section\(draft.briefJson.filledFieldCount == 1 ? "" : "s") captured so far, with \(missingCount) still missing."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: draft.readyToFinalize ? "checkmark.seal.fill" : "square.text.square")
                                .foregroundStyle(draft.readyToFinalize ? .green : .accentColor)

                            Text(draft.readyToFinalize ? "Ready to review" : "Planner brief in progress")
                                .font(.headline)
                        }

                        Text(readinessCopy)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if let suggestedGoal = draft.suggestedGoal, !suggestedGoal.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggested Goal")
                                .font(.headline)
                            Text(suggestedGoal)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("What AgentKVT Understands")
                            .font(.headline)

                        if draft.briefJson.hasContent {
                            ObjectiveBriefSection(title: "Context", items: draft.briefJson.context)
                            ObjectiveBriefSection(title: "Success Criteria", items: draft.briefJson.successCriteria)
                            ObjectiveBriefSection(title: "Constraints", items: draft.briefJson.constraints)
                            ObjectiveBriefSection(title: "Preferences", items: draft.briefJson.preferences)

                            if let deliverable = draft.briefJson.deliverable, !deliverable.isEmpty {
                                ObjectiveBriefSection(title: "Deliverable", items: [deliverable])
                            }

                            ObjectiveBriefSection(title: "Open Questions", items: draft.briefJson.openQuestions)
                        } else {
                            Text("No structured details captured yet. Keep replying in plain language and the planner will fill this in.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if !draft.missingFields.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Still Missing")
                                .font(.headline)

                            ForEach(draft.missingFields, id: \.self) { field in
                                Text(ObjectiveComposerFieldPresentation.humanizedField(field))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    if !draft.plannerSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Planner Summary")
                                .font(.headline)

                            Text(draft.plannerSummary)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Objective Brief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private enum ObjectiveComposerFieldPresentation {
    static func humanizedField(_ field: String) -> String {
        field
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

private extension IOSBackendObjectiveBrief {
    var filledFieldCount: Int {
        [
            !context.isEmpty,
            !successCriteria.isEmpty,
            !constraints.isEmpty,
            !preferences.isEmpty,
            deliverable != nil,
            !openQuestions.isEmpty
        ]
        .filter { $0 }
        .count
    }
}

private struct ObjectiveCreationGuideCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How Objective Creation Works")
                .font(.headline)

            Text("1. Choose a template or start with a custom objective.")
                .font(.subheadline)
                .foregroundStyle(.primary)

            Text("2. The server asks a few clarifying questions and builds a structured planning brief.")
                .font(.subheadline)
                .foregroundStyle(.primary)

            Text("3. Review the final goal and planner summary before creating the objective.")
                .font(.subheadline)
                .foregroundStyle(.primary)

            Text("If guided drafting is unavailable, the app falls back to a standard one-field objective form.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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

private struct ObjectiveComposerTimelineRow: View {
    let item: ObjectiveComposerTimelineItem

    var body: some View {
        switch item {
        case .message(let message):
            ObjectiveComposerMessageBubble(
                speaker: message.role == "user" ? "You" : "Planner",
                content: message.content,
                isUser: message.role == "user"
            )
        case .pendingUser(_, let content):
            ObjectiveComposerMessageBubble(
                speaker: "You",
                content: content,
                isUser: true
            )
            .opacity(0.85)
        case .thinking:
            ObjectiveComposerThinkingBubble()
        }
    }
}

private struct ObjectiveComposerMessageBubble: View {
    let speaker: String
    let content: String
    let isUser: Bool

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
                Text(speaker)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(content)
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

private struct ObjectiveComposerThinkingBubble: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Planner")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Working on the next draft turn…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            Spacer(minLength: 28)
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
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var attachedFileIds: [UUID] = []
    @State private var isUploadingPhotos = false

    var body: some View {
        Form {
            if let fallbackMessage {
                Section {
                    Text(fallbackMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                TextField("e.g. San Diego trip logistics", text: $goal, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Goal")
            } footer: {
                Text("Use a concise outcome-oriented goal. Guided drafting is better for objectives that need constraints, preferences, or follow-up questions.")
            }

            Section {
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 3,
                    matching: .images
                ) {
                    Label(
                        attachedFileIds.isEmpty ? "Add Photos" : "\(attachedFileIds.count) Photo\(attachedFileIds.count == 1 ? "" : "s") Attached",
                        systemImage: attachedFileIds.isEmpty ? "photo.badge.plus" : "photo.stack"
                    )
                }
                .onChange(of: selectedPhotoItems) { _, newItems in
                    Task { await uploadSelectedPhotos(newItems) }
                }

                if isUploadingPhotos {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Uploading photos…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Photos")
            } footer: {
                Text("Photos give the planner visual context. Up to 3 images.")
            }

            Section {
                Toggle("Start immediately (Active)", isOn: $launchActive)
            } footer: {
                Text("Active objectives are created and then immediately sent to the Mac agent for planning.")
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
                .disabled(goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving || isUploadingPhotos)
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
            _ = try await store.createObjective(
                goal: trimmed,
                status: launchActive ? "active" : "pending",
                inboundFileIds: attachedFileIds
            )
            onComplete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func uploadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isUploadingPhotos = true
        attachedFileIds = []
        defer { isUploadingPhotos = false }

        let sync = IOSBackendSyncService()
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let contentType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let fileName = "photo_\(UUID().uuidString).\(ext)"
                let uploaded = try await sync.createInboundFileRemote(
                    fileName: fileName,
                    contentType: contentType,
                    fileData: data,
                    uploadedByProfileId: nil
                )
                attachedFileIds.append(uploaded.id)
            } catch {
                IOSRuntimeLog.log("[LegacyObjectiveCreateView] photo upload failed: \(error)")
            }
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
