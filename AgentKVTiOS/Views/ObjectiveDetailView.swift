import SwiftUI

struct ObjectiveDetailView: View {
    let objective: IOSBackendObjective

    @Environment(ObjectivesStore.self) private var store
    @State private var displayedObjective: IOSBackendObjective
    @State private var detail: IOSBackendObjectiveDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showEditPromptSheet = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    @Environment(\.dismiss) private var dismiss

    init(objective: IOSBackendObjective) {
        self.objective = objective
        _displayedObjective = State(initialValue: objective)
    }

    var body: some View {
        List {
            Section {
                Text(displayedObjective.goal)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Edit prompt") {
                    showEditPromptSheet = true
                }
            } header: {
                Text("Prompt")
            }

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
        .navigationTitle(displayedObjective.goal)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Delete", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
        }
        .confirmationDialog(
            "Delete objective?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteObjective() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tasks and research tied to this objective will be removed.")
        }
        .refreshable { await loadDetail() }
        .overlay {
            if isLoading || isDeleting {
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
        .alert("Could Not Delete Objective", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "An error occurred.")
        }
        .task { await loadDetail() }
        .sheet(isPresented: $showEditPromptSheet) {
            EditObjectivePromptSheet(
                objective: displayedObjective,
                onSaved: { updated in
                    displayedObjective = updated
                    showEditPromptSheet = false
                    Task { await loadDetail() }
                }
            )
        }
    }

    @MainActor
    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            detail = try await store.fetchDetail(for: objective.id)
            if let o = detail?.objective {
                displayedObjective = o
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteObjective() async {
        deleteError = nil
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await store.deleteObjective(id: displayedObjective.id)
            dismiss()
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

// MARK: - Edit prompt

private struct EditObjectivePromptSheet: View {
    let objective: IOSBackendObjective
    var onSaved: (IOSBackendObjective) -> Void

    @Environment(ObjectivesStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var goal: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(objective: IOSBackendObjective, onSaved: @escaping (IOSBackendObjective) -> Void) {
        self.objective = objective
        self.onSaved = onSaved
        _goal = State(initialValue: objective.goal)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    TextField("Goal", text: $goal, axis: .vertical)
                        .lineLimit(4...10)
                }
            }
            .navigationTitle("Edit Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .overlay {
                if isSaving { ProgressView() }
            }
            .alert("Could Not Save Prompt", isPresented: Binding(
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
    private func save() async {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let updated = try await store.updateObjective(
                id: objective.id,
                goal: trimmed,
                status: objective.status,
                priority: objective.priority
            )
            onSaved(updated)
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
