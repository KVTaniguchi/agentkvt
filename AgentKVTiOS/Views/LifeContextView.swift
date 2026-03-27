import SwiftUI
import SwiftData
import ManagerCore

/// LifeContext: edit static facts/preferences the agent consults (goals, location, dates).
struct LifeContextView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LifeContext.key, order: .forward) private var contexts: [LifeContext]
    @State private var showAdd = false

    private let backendSync = IOSBackendSyncService()

    var body: some View {
        NavigationStack {
            List {
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
            .navigationTitle("Life Context")
            .refreshable {
                await backendSync.syncLifeContextEntries(modelContext: modelContext)
            }
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
        .task {
            await backendSync.syncLifeContextEntries(modelContext: modelContext)
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
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let backendSync = IOSBackendSyncService()

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
                        Task { @MainActor in
                            await saveContext()
                        }
                    }
                    .disabled(
                        key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        isSaving
                    )
                }
            }
            .alert("Save Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "The life-context entry could not be saved.")
            }
            .onAppear {
                if let c = context {
                    key = c.key
                    value = c.value
                }
            }
        }
    }

    @MainActor
    private func saveContext() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await backendSync.saveLifeContext(
                existingContext: context,
                key: key,
                value: value,
                modelContext: modelContext
            )
            dismiss()
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
            IOSRuntimeLog.log("[LifeContextEditView] Failed to save life-context key=\(key): \(error)")
        }
    }
}
