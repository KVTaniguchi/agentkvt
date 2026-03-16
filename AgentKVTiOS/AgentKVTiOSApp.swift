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
            AgentLog.self,
            InboundFile.self
        ])
        #if targetEnvironment(simulator)
        // Simulator: use app group container so SwiftData has a valid container (avoids loadIssueModelContainer).
        let config = ModelConfiguration(
            "simulator",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .identifier("group.com.agentkvt.shared"),
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("Simulator ModelContainer (app group) failed: \(error), trying in-memory.")
            let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            if let fallback = try? ModelContainer(for: schema, configurations: [inMemoryConfig]) {
                return fallback
            }
            fatalError("Failed to create ModelContainer in simulator: \(error)")
        }
        #else
        let config = ModelConfiguration(
            "default",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .identifier("group.com.agentkvt.shared"),
            cloudKitDatabase: .private("iCloud.AgentKVT")
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("CloudKit ModelContainer failed: \(error), falling back to in-memory.")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return (try? ModelContainer(for: schema, configurations: [fallback]))
                ?? { fatalError("Fallback in-memory ModelContainer failed: \(error)") }()
        }
        #endif
    }()

    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
        .modelContainer(sharedModelContainer)
    }
}
