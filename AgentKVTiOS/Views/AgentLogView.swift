import SwiftUI
import SwiftData
import ManagerCore

/// Simple audit view: list recent AgentLog entries (reasoning, tool calls, outcomes).
struct AgentLogView: View {
    @Query(sort: \AgentLog.timestamp, order: .reverse) private var logs: [AgentLog]

    var body: some View {
        NavigationStack {
            List {
                ForEach(logs.prefix(100), id: \.id) { log in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(log.phase)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let name = log.missionName {
                                Text(name)
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            Spacer()
                            Text(log.timestamp, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(log.content)
                            .font(.body)
                            .lineLimit(5)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Agent Log")
            .emptyState(logs.isEmpty, message: "No log entries yet. Missions write here when they run on the Mac.")
        }
    }
}
