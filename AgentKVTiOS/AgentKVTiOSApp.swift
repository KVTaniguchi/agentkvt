import SwiftUI
import SwiftData
import ManagerCore

@main
struct AgentKVTiOSApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            LifeContext.self,
            MissionDefinition.self,
            ActionItem.self,
            AgentLog.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
        .modelContainer(sharedModelContainer)
    }
}
