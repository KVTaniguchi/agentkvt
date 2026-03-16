import SwiftUI
import SwiftData
import ManagerCore

/// Dashboard: observe ActionItem and render dynamic AppIntentButtons. No chat.
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ActionItem.timestamp, order: .reverse) private var actionItems: [ActionItem]
    @Query(sort: \InboundFile.timestamp, order: .reverse) private var inboundFiles: [InboundFile]
    @State private var selectedTab = 0
    @State private var isImporterPresented = false
    @State private var importError: String?

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
            InboundFilesView(files: inboundFiles)
                .tabItem { Label("Files", systemImage: "doc") }
                .tag(4)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Upload File", systemImage: "square.and.arrow.up")
                }
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf, .plainText, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    let data = try Data(contentsOf: url)
                    let inbound = InboundFile(
                        fileName: url.lastPathComponent,
                        fileData: data
                    )
                    modelContext.insert(inbound)
                    try modelContext.save()
                } catch {
                    importError = "Failed to import file: \(error.localizedDescription)"
                }
            case .failure(let error):
                importError = "File import failed: \(error.localizedDescription)"
            }
        }
        .alert("File Import Error", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            if let importError {
                Text(importError)
            }
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

struct InboundFilesView: View {
    let files: [InboundFile]

    var body: some View {
        NavigationStack {
            List {
                ForEach(files, id: \.id) { file in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.fileName)
                                .font(.headline)
                            Text(file.timestamp, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(file.isProcessed ? "Processed" : "Pending")
                            .font(.caption2)
                            .padding(6)
                            .background(file.isProcessed ? Color.green.opacity(0.15) : Color.yellow.opacity(0.15))
                            .foregroundStyle(file.isProcessed ? .green : .orange)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .navigationTitle("Inbound Files")
            .emptyState(files.isEmpty, message: "Upload PDFs, TXTs, or CSVs to share with your Mac agent.")
        }
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
