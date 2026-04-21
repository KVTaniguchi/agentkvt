import SwiftUI

struct ResearchResultsView: View {
    let snapshots: [IOSBackendResearchSnapshot]
    let latestFollowUpCard: ObjectiveFeedbackCardModel?
    let historicalFollowUpCards: [ObjectiveFeedbackCardModel]
    let shouldShowAgentActivity: Bool
    let runningTaskCount: Int
    let queuedTaskCount: Int
    let onlineAgentsCount: Int
    let agentActivityMessage: String
    let canContinueResearch: Bool
    let activeConfidenceOptionID: String?
    let activeRatingSnapshotID: UUID?
    let isDispatchingNow: Bool
    let pendingFeedbackSubmission: ObjectiveFeedbackPendingSubmission?

    var followUpCardView: (ObjectiveFeedbackCardModel) -> AnyView
    var onSelectAction: (ObjectiveFeedbackComposerContext) -> Void
    var onSelectConfidenceOption: (IOSBackendResearchSnapshot, ObjectiveConfidenceOption) -> Void
    var onRateResult: (IOSBackendResearchSnapshot, String) -> Void
    var onDispatchNow: (() -> Void)?

    private var sortedSnapshots: [IOSBackendResearchSnapshot] {
        snapshots.sorted { $0.checkedAt > $1.checkedAt }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ResearchSummaryHeader(
                    snapshotCount: snapshots.count,
                    lastCheckedAt: snapshots.map(\.checkedAt).max(),
                    onlineAgentsCount: onlineAgentsCount
                )

                if shouldShowAgentActivity {
                    ResearchAgentActivityCard(
                        runningTaskCount: runningTaskCount,
                        queuedTaskCount: queuedTaskCount,
                        onlineAgentsCount: onlineAgentsCount,
                        message: agentActivityMessage,
                        showsProgress: pendingFeedbackSubmission != nil,
                        isDispatching: isDispatchingNow,
                        onDispatchNow: queuedTaskCount > 0 ? onDispatchNow : nil
                    )
                }

                if let latestFollowUpCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Latest Follow-up")
                            .font(.headline)
                            .padding(.horizontal)
                        followUpCardView(latestFollowUpCard)
                    }
                }

                if sortedSnapshots.isEmpty {
                    Text("No research data yet.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Findings")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(sortedSnapshots) { snapshot in
                            ResearchFindingCard(
                                snapshot: snapshot,
                                canContinueResearch: canContinueResearch,
                                submittingOptionID: activeConfidenceOptionID,
                                isSubmittingRating: activeRatingSnapshotID == snapshot.id,
                                onSelectAction: onSelectAction,
                                onSelectConfidenceOption: { onSelectConfidenceOption(snapshot, $0) },
                                onRateResult: { onRateResult(snapshot, $0) }
                            )
                        }
                    }
                }

                if !historicalFollowUpCards.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Follow-up Loop")
                            .font(.headline)
                            .padding(.horizontal)
                        ForEach(historicalFollowUpCards) { card in
                            followUpCardView(card)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        #if os(iOS)
        .lockPrimaryScrollToVerticalAxis()
        #endif
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Summary Header

private struct ResearchSummaryHeader: View {
    let snapshotCount: Int
    let lastCheckedAt: Date?
    let onlineAgentsCount: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(snapshotCount) finding\(snapshotCount == 1 ? "" : "s")")
                    .font(.headline)
                if let lastCheckedAt {
                    Text("Last checked \(lastCheckedAt, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if onlineAgentsCount > 0 {
                Label("\(onlineAgentsCount) online", systemImage: "circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .labelStyle(TrailingIconLabelStyle())
            } else {
                Text("No agents online")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
                .imageScale(.small)
        }
    }
}

// MARK: - Finding Card

struct ResearchFindingCard: View {
    let snapshot: IOSBackendResearchSnapshot
    let canContinueResearch: Bool
    var submittingOptionID: String? = nil
    var isSubmittingRating = false
    var onSelectAction: (ObjectiveFeedbackComposerContext) -> Void = { _ in }
    var onSelectConfidenceOption: ((ObjectiveConfidenceOption) -> Void)? = nil
    var onRateResult: ((String) -> Void)? = nil

    @State private var actionsExpanded = false

    private var confidenceOptions: [ObjectiveConfidenceOption] {
        ObjectiveConfidenceOptionBuilder.options(for: snapshot)
    }

    private var selectedRating: String? { snapshot.viewerFeedbackRating }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: title + rating chip
            HStack(alignment: .top, spacing: 8) {
                Text(ObjectiveFeedbackPresentation.findingTitle(for: snapshot.key))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let rating = selectedRating {
                    ratingChip(rating)
                }
            }

            // Raw key if title differs
            if ObjectiveFeedbackPresentation.findingTitle(for: snapshot.key) != snapshot.key {
                Text(snapshot.key)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Low-confidence badge
            if ObjectiveFeedbackPresentation.hasLowConfidence(snapshot.value) {
                Text("Low confidence")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.14))
                    .clipShape(Capsule())
            }

            // Value text
            let valueText = ObjectiveFeedbackPresentation.displayText(snapshot.value) ?? snapshot.value
            Text(LocalizedStringKey(valueText))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Delta note
            if let delta = snapshot.deltaNote {
                Label(delta, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Footer: date + feedback counts
            HStack(spacing: 8) {
                Text(snapshot.checkedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if snapshot.goodFeedbackCount > 0 || snapshot.badFeedbackCount > 0 {
                    Spacer()
                    Text("👍 \(snapshot.goodFeedbackCount) · 👎 \(snapshot.badFeedbackCount)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Collapsible actions
            if canContinueResearch {
                DisclosureGroup("What's next?", isExpanded: $actionsExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        // Rating
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Result quality")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                ratingButton(label: "Good result", rating: "good",
                                             systemImage: "hand.thumbsup.fill", tint: .green)
                                ratingButton(label: "Bad result", rating: "bad",
                                             systemImage: "hand.thumbsdown.fill", tint: .orange)
                            }

                            if let rating = selectedRating {
                                Text(ratingSummaryText(for: rating))
                                    .font(.caption)
                                    .foregroundStyle(rating == "good" ? .green : .orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        // Confidence options
                        if !confidenceOptions.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Improve confidence")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                ForEach(confidenceOptions) { option in
                                    confidenceOptionButton(option)
                                }
                            }
                        }

                        // Quick actions
                        VStack(alignment: .leading, spacing: 6) {
                            Text(confidenceOptions.isEmpty ? "Next action" : "Other actions")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                quickActionButton(label: "Approve", tint: .green) {
                                    onSelectAction(context(kind: .finalRecommendation,
                                        draft: "This finding looks right. Use it and turn it into the next recommendation or decision."))
                                }
                                quickActionButton(label: "Go deeper", tint: .blue) {
                                    onSelectAction(context(kind: .followUp,
                                        draft: "Go deeper on this finding and expand the most important details we still need."))
                                }
                            }
                            HStack(spacing: 8) {
                                quickActionButton(label: "Compare", tint: .teal) {
                                    onSelectAction(context(kind: .compareOptions,
                                        draft: "Compare this finding against the strongest alternative and explain which option wins."))
                                }
                                quickActionButton(label: "Challenge", tint: .orange) {
                                    onSelectAction(context(kind: .challengeResult,
                                        draft: "Challenge this finding, verify the assumptions, and tell me what might be wrong."))
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.caption.weight(.semibold))
                .tint(.secondary)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    @ViewBuilder
    private func ratingChip(_ rating: String) -> some View {
        let isGood = rating == "good"
        Text(isGood ? "Good" : "Bad")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isGood ? .green : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((isGood ? Color.green : Color.orange).opacity(0.14))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func ratingButton(label: String, rating: String, systemImage: String, tint: Color) -> some View {
        let button = Button {
            onRateResult?(rating)
        } label: {
            Label(label, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .tint(tint)
        .disabled(submittingOptionID != nil || isSubmittingRating)
        .overlay(alignment: .trailing) {
            if isSubmittingRating {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 8)
            }
        }

        if selectedRating == rating {
            button.buttonStyle(BorderedProminentButtonStyle())
        } else {
            button.buttonStyle(BorderedButtonStyle())
        }
    }

    @ViewBuilder
    private func confidenceOptionButton(_ option: ObjectiveConfidenceOption) -> some View {
        Button {
            onSelectConfidenceOption?(option)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: option.feedbackKind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(option.feedbackKind.tint)
                    .padding(.top, 2)

                Text(option.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                if submittingOptionID == option.id {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(12)
            .background(option.feedbackKind.tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(submittingOptionID != nil)
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
        .disabled(submittingOptionID != nil)
    }

    private func ratingSummaryText(for rating: String) -> String {
        let prefix = rating == "good" ? "Marked good" : "Marked bad"
        if let reason = snapshot.viewerFeedbackReason,
           !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(prefix): \(reason)"
        }
        return prefix
    }

    private func context(kind: ObjectiveFeedbackKindOption, draft: String) -> ObjectiveFeedbackComposerContext {
        ObjectiveFeedbackComposerContext(
            existingFeedback: nil,
            feedbackKind: kind.rawValue,
            targetID: ObjectiveFeedbackTarget.id(taskId: nil, researchSnapshotId: snapshot.id),
            draft: draft
        )
    }
}
