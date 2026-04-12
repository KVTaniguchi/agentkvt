import Foundation

struct IOSBackendSettingsSource: Sendable {
    let environment: [String: String]
    let groupContainerURL: URL?

    static func live() -> IOSBackendSettingsSource {
        IOSBackendSettingsSource(
            environment: ProcessInfo.processInfo.environment,
            groupContainerURL: nil
        )
    }
}

struct IOSBackendSettings: Sendable {
    let configFileURL: URL?
    let apiBaseURL: URL?
    let workspaceSlug: String?
    /// When set (with `ollamaModel`), chat sends directly to this Ollama HTTP API on Wi‑Fi/LAN instead of queueing for the Mac runner.
    let ollamaBaseURL: URL?
    let ollamaModel: String?

    var isEnabled: Bool {
        apiBaseURL != nil
    }

    /// Direct Ollama chat on device (same host/model as the Mac runner typically uses).
    var isDirectOllamaConfigured: Bool {
        guard ollamaBaseURL != nil, let model = ollamaModel?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty else {
            return false
        }
        return true
    }

    var startupMessage: String {
        let backend = apiBaseURL?.absoluteString ?? "disabled"
        let workspace = workspaceSlug ?? "-"
        let ollama = isDirectOllamaConfigured ? "direct Ollama \(ollamaModel ?? "") @ \(ollamaBaseURL!.absoluteString)" : "no direct Ollama"
        return "[Config] iOS backend: \(backend) [workspace=\(workspace)] | \(ollama)"
    }

    static func load(from source: IOSBackendSettingsSource = .live()) -> IOSBackendSettings {
        let configFileURL = source.groupContainerURL?
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "agentkvt-runner.plist", directoryHint: .notDirectory)

        let configValues = configFileURL.flatMap(loadConfigDictionary(at:)) ?? [:]
        let bundleInfo = Bundle.main.infoDictionary ?? [:]
        let resolver = IOSBackendValueResolver(
            environment: source.environment,
            configValues: configValues,
            bundleInfo: bundleInfo
        )
        let apiBaseURL = resolver.string(for: "AGENTKVT_API_BASE_URL").flatMap(URL.init(string:))
        let workspaceSlug = resolver.string(for: "AGENTKVT_WORKSPACE_SLUG") ?? (apiBaseURL == nil ? nil : "default")
        let ollamaURLString = resolver.string(for: "AGENTKVT_OLLAMA_BASE_URL")
            ?? resolver.string(for: "OLLAMA_BASE_URL")
        let ollamaBaseURL = ollamaURLString.flatMap(URL.init(string:))
        let ollamaModel = resolver.string(for: "AGENTKVT_OLLAMA_MODEL")
            ?? resolver.string(for: "OLLAMA_MODEL")

        return IOSBackendSettings(
            configFileURL: configFileURL,
            apiBaseURL: apiBaseURL,
            workspaceSlug: workspaceSlug,
            ollamaBaseURL: ollamaBaseURL,
            ollamaModel: ollamaModel
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
    let bundleInfo: [String: Any]

    func string(for key: String) -> String? {
        if let value = environment[key], !value.isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let value = UserDefaults.standard.string(forKey: key), !value.isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        switch configValues[key] {
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber:
            return number.stringValue
        default:
            break
        }

        switch bundleInfo[key] {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }
}
