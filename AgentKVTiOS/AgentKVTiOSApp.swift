import SwiftUI

@main
struct AgentKVTiOSApp: App {
    @StateObject private var familyProfileStore = FamilyProfileStore()

    @State private var familyMembersStore: FamilyMembersStore
    @State private var lifeContextStore: LifeContextStore
    @State private var agentLogsStore: AgentLogsStore
    @State private var actionsStore: ActionsStore
    @State private var objectivesStore: ObjectivesStore
    @State private var chatStore: ChatStore
    @State private var inboundFilesStore: InboundFilesStore

    init() {
        let logFile = IOSRuntimeLog.bootstrap(processLabel: "AgentKVTiOSApp")
        IOSRuntimeLog.log("[Logging] Writing logs to \(logFile.path)")
        IOSRuntimeLog.log(IOSBackendSettings.load().startupMessage)

        let sync = IOSBackendSyncService()
        _familyMembersStore = State(wrappedValue: FamilyMembersStore(sync: sync))
        _lifeContextStore = State(wrappedValue: LifeContextStore(sync: sync))
        _agentLogsStore = State(wrappedValue: AgentLogsStore(sync: sync))
        _actionsStore = State(wrappedValue: ActionsStore(sync: sync))
        _objectivesStore = State(wrappedValue: ObjectivesStore(sync: sync))
        _chatStore = State(wrappedValue: ChatStore(sync: sync))
        _inboundFilesStore = State(wrappedValue: InboundFilesStore(sync: sync))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(familyProfileStore)
                .environment(familyMembersStore)
                .environment(lifeContextStore)
                .environment(agentLogsStore)
                .environment(actionsStore)
                .environment(objectivesStore)
                .environment(chatStore)
                .environment(inboundFilesStore)
        }
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
