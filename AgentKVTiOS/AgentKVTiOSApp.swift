import SwiftUI
import SwiftData
import ManagerCore

let iosSharedAppGroupIdentifier = "group.com.agentkvt.shared"
let iosCloudKitContainerIdentifier = "iCloud.AgentKVT"

@main
struct AgentKVTiOSApp: App {
    @StateObject private var familyProfileStore = FamilyProfileStore()

    var sharedModelContainer: ModelContainer = {
        let logFile = IOSRuntimeLog.bootstrap(processLabel: "AgentKVTiOSApp")
        IOSRuntimeLog.log("[Logging] Writing logs to \(logFile.path)")
        let schema = Schema([
            LifeContext.self,
            MissionDefinition.self,
            ActionItem.self,
            AgentLog.self,
            InboundFile.self,
            ChatThread.self,
            ChatMessage.self,
            IncomingEmailSummary.self,
            WorkUnit.self,
            EphemeralPin.self,
            ResourceHealth.self,
            FamilyMember.self,
        ])
        #if targetEnvironment(simulator)
        // Simulator: use app group container so SwiftData has a valid container (avoids loadIssueModelContainer).
        let config = ModelConfiguration(
            "simulator",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .identifier(iosSharedAppGroupIdentifier),
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            IOSRuntimeLog.log("SwiftData storage: simulator app group only (CloudKit disabled)")
            return container
        } catch {
            IOSRuntimeLog.log("Simulator ModelContainer (app group) failed: \(error), trying in-memory.")
            let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            if let fallback = try? ModelContainer(for: schema, configurations: [inMemoryConfig]) {
                IOSRuntimeLog.log("SwiftData storage: simulator in-memory fallback")
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
            groupContainer: .identifier(iosSharedAppGroupIdentifier),
            cloudKitDatabase: .private(iosCloudKitContainerIdentifier)
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            IOSRuntimeLog.log("SwiftData storage: app group + CloudKit")
            return container
        } catch {
            IOSRuntimeLog.log("CloudKit ModelContainer failed: \(error), falling back to in-memory.")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            IOSRuntimeLog.log("SwiftData storage: in-memory fallback")
            return (try? ModelContainer(for: schema, configurations: [fallback]))
                ?? { fatalError("Fallback in-memory ModelContainer failed: \(error)") }()
        }
        #endif
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(familyProfileStore)
        }
        .modelContainer(sharedModelContainer)
    }
}

enum IOSRuntimeLog {
    private static let queue = DispatchQueue(label: "IOSRuntimeLog")
    private static var isConfigured = false
    private static var logHandle: FileHandle?
    private static var configuredProcessLabel = "AgentKVTiOSApp"

    @discardableResult
    static func bootstrap(processLabel: String = "AgentKVTiOSApp") -> URL {
        let destination = resolvedLogFileURL()
        queue.sync {
            configuredProcessLabel = processLabel
            guard !isConfigured else { return }

            prepareLogFile(at: destination)
            logHandle = try? FileHandle(forWritingTo: destination)
            let _ = try? logHandle?.seekToEnd()
            writeUnlocked(
                """

                ===== AgentKVT session started \(timestamp()) [\(processLabel)] pid=\(ProcessInfo.processInfo.processIdentifier) =====
                """
            )
            isConfigured = true
        }
        return destination
    }

    static func log(_ message: String) {
        let _ = bootstrap(processLabel: configuredProcessLabel)
        let payload = "[\(timestamp())] \(message)"
        queue.async {
            writeUnlocked(payload)
        }
        print(message)
    }

    static var availableLogFileURL: URL? {
        let candidate = resolvedLogFileURL()
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private static func resolvedLogFileURL() -> URL {
        if let sharedContainerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: iosSharedAppGroupIdentifier
        ) {
            return sharedContainerURL.appending(path: "Library/Logs/agentkvt-ios.log")
        }

        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return appSupportURL.appending(path: "agentkvt-ios.log")
    }

    private static func prepareLogFile(at url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            let _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    private static func writeUnlocked(_ string: String) {
        guard let data = (string + "\n").data(using: .utf8) else { return }
        try? logHandle?.write(contentsOf: data)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
