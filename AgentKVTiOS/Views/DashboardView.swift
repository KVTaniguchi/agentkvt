import SwiftUI
import SwiftData
import ManagerCore

/// Dashboard: observe ActionItem and render dynamic AppIntentButtons. No chat.
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ActionItem.timestamp, order: .reverse) private var actionItems: [ActionItem]
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ActionItemsList(items: actionItems)
                .tabItem { Label("Actions", systemImage: "square.grid.2x2") }
                .tag(0)
            MissionListView()
                .tabItem { Label("Missions", systemImage: "list.bullet") }
                .tag(1)
            LifeContextView()
                .tabItem { Label("Context", systemImage: "person.crop.circle") }
                .tag(2)
            AgentLogView()
                .tabItem { Label("Log", systemImage: "doc.text.magnifyingglass") }
                .tag(3)
        }
    }
}

struct ActionItemsList: View {
    let items: [ActionItem]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            List {
                ForEach(items.filter { !$0.isHandled }, id: \.id) { item in
                    ActionItemRow(item: item) {
                        item.isHandled = true
                        try? modelContext.save()
                    }
                }
            }
            .navigationTitle("Actions")
            .emptyState(items.isEmpty, message: "No action items. Missions on the Mac will create them.")
        }
    }
}

struct ActionItemRow: View {
    let item: ActionItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(item.systemIntent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

extension View {
    @ViewBuilder
    func emptyState(_ isEmpty: Bool, message: String) -> some View {
        if isEmpty {
            ContentUnavailableView("No items", systemImage: "tray", description: Text(message))
        } else {
            self
        }
    }
}
