import SwiftUI

struct ObjectivesDashboardView: View {
    @Environment(ObjectivesStore.self) private var store
    @State private var showCreateSheet = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.objectives) { objective in
                    NavigationLink(destination: ObjectiveDetailView(objective: objective)) {
                        ObjectiveRow(objective: objective)
                    }
                }
            }
            .navigationTitle("Objectives")
            .refreshable { await store.refresh() }
            .overlay {
                if store.isLoading && store.objectives.isEmpty {
                    ProgressView()
                }
            }
            .emptyState(store.objectives.isEmpty && !store.isLoading,
                        message: "No objectives yet. Tap + to create one.")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateObjectiveSheet()
            }
            .familyProfileToolbar()
        }
        .task { await store.refresh() }
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

// MARK: - Create sheet

struct CreateObjectiveSheet: View {
    @Environment(ObjectivesStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var goal = ""
    @State private var launchActive = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("e.g. San Diego trip logistics", text: $goal, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section {
                    Toggle("Start immediately (Active)", isOn: $launchActive)
                } footer: {
                    Text("Active objectives trigger the Mac agent to decompose tasks automatically.")
                }
            }
            .navigationTitle("New Objective")
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
            .alert("Could Not Create Objective", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "An error occurred.")
            }
            .overlay {
                if isSaving { ProgressView() }
            }
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
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
