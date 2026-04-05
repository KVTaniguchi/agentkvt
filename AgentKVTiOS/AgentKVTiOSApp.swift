import SwiftUI
import SwiftData
import ManagerCore

@main
struct AgentKVTiOSApp: App {
    @StateObject private var familyProfileStore = FamilyProfileStore()

    @State private var actionsStore: ActionsStore
    @State private var objectivesStore: ObjectivesStore

    init() {
        let sync = IOSBackendSyncService()
        _actionsStore = State(wrappedValue: ActionsStore(sync: sync))
        _objectivesStore = State(wrappedValue: ObjectivesStore(sync: sync))
    }

    var sharedModelContainer: ModelContainer = {
        let logFile = IOSRuntimeLog.bootstrap(processLabel: "AgentKVTiOSApp")
        IOSRuntimeLog.log("[Logging] Writing logs to \(logFile.path)")
        IOSRuntimeLog.log(IOSBackendSettings.load().startupMessage)
        let schema = Schema([
            LifeContext.self,
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
            ResearchSnapshot.self,
        ])
        let config = ModelConfiguration(
            "default",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            IOSRuntimeLog.log("SwiftData storage: local app sandbox only (CloudKit disabled)")
            return container
        } catch {
            IOSRuntimeLog.log("Local ModelContainer failed: \(error), falling back to in-memory.")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            IOSRuntimeLog.log("SwiftData storage: in-memory fallback")
            return (try? ModelContainer(for: schema, configurations: [fallback]))
                ?? { fatalError("Fallback in-memory ModelContainer failed: \(error)") }()
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(familyProfileStore)
                .environment(actionsStore)
                .environment(objectivesStore)
        }
        .modelContainer(sharedModelContainer)
    }
}

enum IOSRuntimeLog {
    private static let queue = DispatchQueue(label: "IOSRuntimeLog")
    private static var isConfigured = false
    private static var logHandle: FileHandle?
    private static var configuredProcessLabel = "AgentKVTiOSApp"
    private static let clientBuildMetadata = resolvedClientBuildMetadata()

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

                ===== AgentKVT session started \(timestamp()) [\(processLabel)] [\(clientBuildMetadata)] pid=\(ProcessInfo.processInfo.processIdentifier) =====
                """
            )
            isConfigured = true
        }
        return destination
    }

    static func log(_ message: String) {
        let _ = bootstrap(processLabel: configuredProcessLabel)
        let payload = "[\(timestamp())] [\(clientBuildMetadata)] \(message)"
        queue.async {
            writeUnlocked(payload)
        }
        print(payload)
    }

    static var availableLogFileURL: URL? {
        let candidate = resolvedLogFileURL()
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private static func resolvedLogFileURL() -> URL {
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

    private static func resolvedClientBuildMetadata() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (info["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch (version, build) {
        case let (.some(version), .some(build)) where !version.isEmpty && !build.isEmpty:
            return "client \(version) build \(build)"
        case let (_, .some(build)) where !build.isEmpty:
            return "client build \(build)"
        case let (.some(version), _) where !version.isEmpty:
            return "client \(version)"
        default:
            return "client build unknown"
        }
    }
}
