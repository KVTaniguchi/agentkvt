import SwiftUI
import ManagerCore

// MARK: - Design: Single nav title, consistent actions, horizontal context chips, unified buttons

struct GoalDetailView: View {
    let goalTitle: String
    var lastInteraction: String = "Need clarification from user (confidence: 0%)"
    var contextAnalyzers: [ContextChip] = []
    var suggestionCount: Int = 3
    /// When true, the suggestions card shows a prominent "thinking" state instead of a tiny spinner.
    var isLoadingSuggestions: Bool = false
    var onViewActivityHistory: (() -> Void)?
    var onSuggestions: (() -> Void)?
    var onCreateNotification: (() -> Void)?
    var onCreateReminder: (() -> Void)?
    var onOpenChat: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Top of mind card — nav title is source of truth; no repeated large title
                topOfMindCard

                // 2. Context analyzers — horizontal scroll, consistent pill alignment
                contextAnalyzersSection

                // 3. Suggestions — consistent tappable card with chevron
                suggestionsCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .navigationTitle(goalTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { } label: {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomActions
        }
    }

    // MARK: - Top of mind (no redundant title; activity = text link + chevron)
    private var topOfMindCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "target")
                    .foregroundStyle(.blue)
                Text("Top of mind")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Last interaction: \(lastInteraction)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(action: { onViewActivityHistory?() }) {
                HStack {
                    Image(systemName: "clock")
                    Text("View activity history")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Context analyzers: horizontal scroll, standard pill height, vertical alignment
    private var contextAnalyzersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Context analyzers")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(contextAnalyzers) { chip in
                        ContextChipView(chip: chip)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Suggestions — whole card tappable; when loading, option 6: pulsing card + status text
    private var suggestionsCard: some View {
        Group {
            if isLoadingSuggestions {
                suggestionsThinkingCard
            } else {
                Button(action: { onSuggestions?() }) {
                    suggestionsCardContent(count: suggestionCount, showChevron: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Option 6: Same card with subtle pulse/glow; subtitle "Thinking of ideas…" + medium spinner.
    private var suggestionsThinkingCard: some View {
        HStack {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Suggestions for today")
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Text("Thinking of ideas…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    Color.orange.opacity(suggestionsPulseOpacity),
                    lineWidth: 1.5
                )
        )
        .task(id: isLoadingSuggestions) {
            guard isLoadingSuggestions else { return }
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.5)) { suggestionsPulsePhase.toggle() }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generating suggestions. Please wait.")
        .accessibilityAddTraits(.updatesFrequently)
    }

    @State private var suggestionsPulsePhase: Bool = false
    private var suggestionsPulseOpacity: Double { suggestionsPulsePhase ? 0.55 : 0.2 }

    private func suggestionsCardContent(count: Int, showChevron: Bool) -> some View {
        HStack {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Suggestions for today")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(count) ideas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Unified bottom actions: same height & radius; primary full-width
    private var bottomActions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                secondaryButton(
                    title: "Create Notification",
                    icon: "bell.fill",
                    color: .blue,
                    action: { onCreateNotification?() }
                )
                secondaryButton(
                    title: "Create Reminder",
                    icon: "checkmark.circle.fill",
                    color: .green,
                    action: { onCreateReminder?() }
                )
            }
            Button(action: { onOpenChat?() }) {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text("Open chat (optional)")
                }
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color(uiColor: .tertiaryLabel))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func secondaryButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Context chip: fixed height & padding for alignment
struct ContextChip: Identifiable {
    let id = UUID()
    let label: String
    let subtitle: String?
    let color: Color
    let systemImage: String
}

struct ContextChipView: View {
    let chip: ContextChip

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: chip.systemImage)
                .font(.caption)
            if let sub = chip.subtitle, !sub.isEmpty {
                Text("\(chip.label): \(sub)")
                    .font(.caption)
            } else {
                Text(chip.label)
                    .font(.caption)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(chip.color)
        .clipShape(Capsule())
    }
}

// MARK: - Preview + sample data
#Preview("Ready") {
    NavigationStack {
        GoalDetailView(
            goalTitle: "Lower my blood pressure",
            lastInteraction: "Need clarification from user (confidence: 0%)",
            contextAnalyzers: [
                ContextChip(label: "Health data", subtitle: "3d ago", color: .red, systemImage: "heart.text.square"),
                ContextChip(label: "Location", subtitle: nil, color: .orange, systemImage: "paperplane"),
            ],
            suggestionCount: 3,
            isLoadingSuggestions: false
        )
    }
}

#Preview("Thinking (suggestions loading)") {
    NavigationStack {
        GoalDetailView(
            goalTitle: "Lower my blood pressure",
            lastInteraction: "Need clarification from user (confidence: 0%)",
            contextAnalyzers: [
                ContextChip(label: "Health data", subtitle: "3d ago", color: .red, systemImage: "heart.text.square"),
                ContextChip(label: "Location", subtitle: nil, color: .orange, systemImage: "paperplane"),
            ],
            suggestionCount: 0,
            isLoadingSuggestions: true
        )
    }
}
