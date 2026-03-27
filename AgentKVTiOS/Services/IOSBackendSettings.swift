import Foundation

struct IOSBackendSettingsSource: Sendable {
    let environment: [String: String]
    let groupContainerURL: URL?

    static func live() -> IOSBackendSettingsSource {
        IOSBackendSettingsSource(
            environment: ProcessInfo.processInfo.environment,
            groupContainerURL: FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: iosSharedAppGroupIdentifier
            )
        )
    }
}

struct IOSBackendSettings: Sendable {
    let configFileURL: URL?
    let apiBaseURL: URL?
    let workspaceSlug: String?

    var isEnabled: Bool {
        apiBaseURL != nil
    }

    var startupMessage: String {
        let backend = apiBaseURL?.absoluteString ?? "disabled"
        let workspace = workspaceSlug ?? "-"
        return "[Config] iOS backend: \(backend) [workspace=\(workspace)]"
    }

    static func load(from source: IOSBackendSettingsSource = .live()) -> IOSBackendSettings {
        let configFileURL = source.groupContainerURL?
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "agentkvt-runner.plist", directoryHint: .notDirectory)

        let configValues = configFileURL.flatMap(loadConfigDictionary(at:)) ?? [:]
        let resolver = IOSBackendValueResolver(environment: source.environment, configValues: configValues)
        let apiBaseURL = resolver.string(for: "AGENTKVT_API_BASE_URL").flatMap(URL.init(string:))
        let workspaceSlug = resolver.string(for: "AGENTKVT_WORKSPACE_SLUG") ?? (apiBaseURL == nil ? nil : "default")

        return IOSBackendSettings(
            configFileURL: configFileURL,
            apiBaseURL: apiBaseURL,
            workspaceSlug: workspaceSlug
        )
    }

    private static func loadConfigDictionary(at url: URL) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let raw = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            return raw as? [String: Any]
        } catch {
            IOSRuntimeLog.log("[IOSBackendSettings] Failed to load config at \(url.path): \(error)")
            return nil
        }
    }
}

private struct IOSBackendValueResolver {
    let environment: [String: String]
    let configValues: [String: Any]

    func string(for key: String) -> String? {
        if let value = environment[key], !value.isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        switch configValues[key] {
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }
}
