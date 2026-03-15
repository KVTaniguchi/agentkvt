import SwiftUI
import SwiftData
import ManagerCore

/// LifeContext: edit static facts/preferences the agent consults (goals, location, dates).
struct LifeContextView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LifeContext.key, order: .forward) private var contexts: [LifeContext]
    @State private var showAdd = false

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
