import SwiftUI

struct ObjectivesDashboardView: View {
    @Environment(ObjectivesStore.self) private var store
    @State private var showCreateSheet = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            List {
                if let err = store.errorMessage, !err.isEmpty {
                    Section {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(store.objectives) { objective in
                    NavigationLink(destination: ObjectiveDetailView(objective: objective)) {
                        ObjectiveRow(objective: objective)
                    }
                }
                .onDelete(perform: deleteObjectives)
            }
            .navigationTitle("Objectives")
            .refreshable { await store.refresh() }
            .overlay {
                if store.isLoading && store.objectives.isEmpty {
                    ProgressView()
                }
            }
            .emptyState(
                store.objectives.isEmpty && !store.isLoading && store.errorMessage == nil,
                message: "No objectives yet. Tap + to start a guided draft or create one directly."
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fullScreenCover(isPresented: $showCreateSheet) {
                ObjectiveComposerView()
            }
            .familyProfileToolbar()
            .alert("Could Not Delete Objective", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) { deleteError = nil }
            } message: {
                Text(deleteError ?? "An error occurred.")
            }
        }
        .task { await store.refresh() }
    }

    private func deleteObjectives(at offsets: IndexSet) {
        let ids = offsets.compactMap { store.objectives.indices.contains($0) ? store.objectives[$0].id : nil }
        Task { @MainActor in
            for id in ids {
                do {
                    try await store.deleteObjective(id: id)
                } catch {
                    deleteError = error.localizedDescription
                    IOSRuntimeLog.log("[ObjectivesDashboardView] Delete failed: \(error)")
                }
            }
        }
    }
}

// MARK: - Row

struct ObjectiveRow: View {
    let objective: IOSBackendObjective

    private var statusColor: Color {
        switch objective.status {
        case "active":    return .green
        case "completed": return .blue
        case "archived":  return .gray
        default:          return .orange   // pending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(objective.goal)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(objective.status.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.85))
                    .clipShape(Capsule())
                if objective.priority > 0 {
                    Label("\(objective.priority)", systemImage: "arrow.up.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(objective.updatedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
