import SwiftUI
import SwiftData
import ManagerCore

/// LifeContext: edit static facts/preferences the agent consults (goals, location, dates).
struct LifeContextView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LifeContext.key, order: .forward) private var contexts: [LifeContext]
    @State private var showAdd = false

    private var goalTitles: [String] {
        guard let goalsContext = contexts.first(where: { $0.key.lowercased() == "goals" }),
              !goalsContext.value.isEmpty else {
            return ["Lower my blood pressure"] // demo row when no goals context
        }
        return goalsContext.value
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Top of mind") {
                    ForEach(goalTitles, id: \.self) { title in
                        NavigationLink(title) {
                            GoalDetailView(
                                goalTitle: title,
                                lastInteraction: "Need clarification from user (confidence: 0%)",
                                contextAnalyzers: [
                                    ContextChip(label: "Health data", subtitle: "3d ago", color: .red, systemImage: "heart.text.square"),
                                    ContextChip(label: "Location", subtitle: nil, color: .orange, systemImage: "paperplane"),
                                ],
                                suggestionCount: 3
                            )
                        }
                    }
                }
                Section("Facts & preferences") {
                    ForEach(contexts, id: \.id) { ctx in
                        NavigationLink {
                            LifeContextEditView(context: ctx) {}
                        } label: {
                            HStack {
                                Text(ctx.key)
                                    .font(.headline)
                                Spacer()
                                Text(ctx.value)
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Life Context")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") { showAdd = true }
                }
            }
            .sheet(isPresented: $showAdd) {
                LifeContextEditView(context: nil) {
                    showAdd = false
                }
            }
        }
    }
}

struct LifeContextEditView: View {
    let context: LifeContext?
    let onDismiss: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var key: String = ""
    @State private var value: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Key (e.g. goals, location)", text: $key)
                TextField("Value", text: $value, axis: .vertical)
                    .lineLimit(2...6)
            }
            .navigationTitle(context == nil ? "New fact" : "Edit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss(); onDismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let ctx = context {
                            ctx.key = key
                            ctx.value = value
                            ctx.updatedAt = Date()
                        } else {
                            let ctx = LifeContext(key: key, value: value)
                            modelContext.insert(ctx)
                        }
                        try? modelContext.save()
                        dismiss()
                        onDismiss()
                    }
                    .disabled(key.isEmpty)
                }
            }
            .onAppear {
                if let c = context {
                    key = c.key
                    value = c.value
                }
            }
        }
    }
}
