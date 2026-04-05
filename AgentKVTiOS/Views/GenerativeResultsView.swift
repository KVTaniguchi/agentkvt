import ManagerCore
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

// MARK: - Generative results view

struct GenerativeResultsView: View {
    let objectiveId: UUID
    let objectiveGoal: String
    let snapshots: [IOSBackendResearchSnapshot]

    @Environment(ObjectivesStore.self) private var store
    @State private var layout: UINode?
    @State private var isLoading = false
    @State private var useFallback = false

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
                    NodeView(node: layout)
                        .padding()
                }
                .background(Color(.systemGroupedBackground))
            } else {
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
        .task { await loadPresentation() }
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
