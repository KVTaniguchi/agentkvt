import CloudKit
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
        IOSRuntimeLog.log(IOSBackendSettings.load().startupMessage)
        logIOSCloudKitDiagnostics()
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
            ResearchSnapshot.self,
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

private func logIOSCloudKitDiagnostics() {
    let container = CKContainer(identifier: iosCloudKitContainerIdentifier)
    IOSRuntimeLog.log("[CloudKitDiagnostics] Container: \(iosCloudKitContainerIdentifier)")
    container.accountStatus { status, error in
        if let error {
            IOSRuntimeLog.log("[CloudKitDiagnostics] accountStatus error: \(error)")
            return
        }
        IOSRuntimeLog.log("[CloudKitDiagnostics] accountStatus: \(describeIOSCloudKitAccountStatus(status))")
    }
    container.fetchUserRecordID { recordID, error in
        if let error {
            IOSRuntimeLog.log("[CloudKitDiagnostics] userRecordID error: \(error)")
            return
        }
        guard let recordID else {
            IOSRuntimeLog.log("[CloudKitDiagnostics] userRecordID: nil")
            return
        }
        IOSRuntimeLog.log("[CloudKitDiagnostics] userRecordID: \(recordID.recordName) zone=\(recordID.zoneID.zoneName)")
    }
}

private func describeIOSCloudKitAccountStatus(_ status: CKAccountStatus) -> String {
    switch status {
    case .available:
        return "available"
    case .couldNotDetermine:
        return "couldNotDetermine"
    case .noAccount:
        return "noAccount"
    case .restricted:
        return "restricted"
    case .temporarilyUnavailable:
        return "temporarilyUnavailable"
    @unknown default:
        return "unknown(\(status.rawValue))"
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
