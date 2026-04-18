import SwiftUI

struct AgentSensesView: View {
    @State private var shareLocation: Bool = false
    @State private var shareCalendar: Bool = false
    @State private var isSyncing: Bool = false
    @State private var syncError: String?

    var body: some View {
        Form {
            Section(header: Text("Agent Identity (Email)")) {
                Text("Placeholder for Agent Email configuration.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(
                header: Text("Agent Senses"),
                footer: Text("Senses allow the agent to consider your physical location and schedule when making logistical recommendations.")
            ) {
                Toggle(isOn: $shareLocation) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Location & Weather")
                            .font(.body)
                        Text("Allows the agent to see your current city and local weather to recommend appropriate actions.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .onChange(of: shareLocation) { _, newValue in
                    if newValue {
                        ClientTelemetryService.shared.requestLocationPermission()
                        Task { await syncSnapshot() }
                    }
                }

                Toggle(isOn: $shareCalendar) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Calendar Access")
                            .font(.body)
                        Text("Allows the agent to see your schedule for the next 48 hours to avoid interrupting busy periods.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .onChange(of: shareCalendar) { _, newValue in
                    if newValue {
                        Task {
                            let granted = await ClientTelemetryService.shared.requestCalendarPermission()
                            if granted {
                                await syncSnapshot()
                            } else {
                                shareCalendar = false
                            }
                        }
                    }
                }

                if shareCalendar {
                    NavigationLink("Select Calendars") {
                        Text("Calendar selection view coming soon...")
                    }
                }
            }

            if isSyncing {
                HStack {
                    Spacer()
                    ProgressView("Updating Agent Context...")
                    Spacer()
                }
            } else if let error = syncError {
                Text(error).foregroundColor(.red).font(.caption)
            }
        }
        .navigationTitle("Agent Configuration")
    }

    private func syncSnapshot() async {
        guard shareLocation || shareCalendar else { return }
        isSyncing = true
        syncError = nil
        do {
            let payload = await ClientTelemetryService.shared.buildSnapshotPayload()
            let syncService = IOSBackendSyncService()
            try await syncService.postClientTelemetrySnapshotRemote(payload: payload)
        } catch {
            syncError = "Failed to synchronize context with the agent."
        }
        isSyncing = false
    }
}
