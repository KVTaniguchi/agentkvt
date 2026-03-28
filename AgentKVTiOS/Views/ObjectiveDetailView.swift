import SwiftUI

struct ObjectiveDetailView: View {
    let objective: IOSBackendObjective

    @Environment(ObjectivesStore.self) private var store
    @State private var detail: IOSBackendObjectiveDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            // Tasks
            Section {
                if let tasks = detail?.tasks, !tasks.isEmpty {
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

            // Research Snapshots
            Section {
                if let snapshots = detail?.researchSnapshots, !snapshots.isEmpty {
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
        }
        .navigationTitle(objective.goal)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadDetail() }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .alert("Could Not Load Detail", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An error occurred.")
        }
        .task { await loadDetail() }
    }

    @MainActor
    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            detail = try await store.fetchDetail(for: objective.id)
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
            Text(snapshot.key)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(snapshot.value)
                .font(.headline)
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
