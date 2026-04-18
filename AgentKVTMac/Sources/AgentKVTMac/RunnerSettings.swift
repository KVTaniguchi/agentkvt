import Foundation

struct RunnerSettingsSource: Sendable {
    let environment: [String: String]
    let bundleIdentifier: String?
    let groupContainerURL: URL?
    let homeDirectory: URL

    var isAppBundle: Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return true
    }

    static func live() -> RunnerSettingsSource {
        RunnerSettingsSource(
            environment: ProcessInfo.processInfo.environment,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            groupContainerURL: FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: sharedAppGroupIdentifier
            ),
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }
}

struct RunnerSettings: Sendable {
    let source: RunnerSettingsSource
    let configFileURL: URL
    let configFileLoaded: Bool
    let configFileError: String?
    let runScheduler: Bool
    let schedulerIntervalSeconds: Int
    let objectiveWorkerConcurrency: Int
    let ollamaBaseURL: URL
    let ollamaModel: String
    let ollamaAPIKey: String?
    let geminiAPIKey: String?
    let backendBaseURL: URL?
    let backendWorkspaceSlug: String?
    let backendAgentToken: String?
    let notificationEmail: String?
    let agentMailAPIKey: String?
    let agentMailInboxId: String?
    let agentMailDisplayName: String?
    let agentMailUsername: String?
    let agentMailDomain: String?
    let agentMailInboxClientId: String?
    let agentMailPythonExecutable: String
    let agentMailPollSeconds: Int
    let githubPAT: String?
    let githubAllowedRepos: [String]
    let inboxDirectory: URL?
    let inboundDirectory: URL?
    let localFileAllowedDirectories: [URL]
    let webhookPort: UInt16
    /// When set, registered with the API so `TaskExecutorJob` can POST to a URL reachable from the server (Tailscale, ngrok, LAN IP). If nil, defaults to `http://127.0.0.1:<WEBHOOK_PORT>` (only works when Rails runs on the same machine as this runner).
    let agentWebhookPublicURL: String?
    let disableCloudKit: Bool
    let imapHost: String?
    let imapPort: Int
    let imapUsername: String?
    let imapPassword: String?
    let imapMailbox: String
    let imapPollSeconds: Int

    var agentMailEnabled: Bool { agentMailAPIKey != nil }
    var imapEnabled: Bool { imapHost != nil && imapUsername != nil && imapPassword != nil }

    var isAppBundle: Bool {
        source.isAppBundle
    }

    var startupMessages: [String] {
        var messages: [String] = []
        if configFileLoaded {
            messages.append("[Config] Loaded runtime config from \(configFileURL.path)")
        } else if let configFileError {
            messages.append("[Config] Failed to load runtime config at \(configFileURL.path): \(configFileError)")
            messages.append("[Config] Continuing with defaults and environment overrides.")
        } else {
            messages.append("[Config] No runtime config file at \(configFileURL.path); using defaults and environment overrides.")
        }

        let mode = runScheduler ? "scheduler" : "single-test"
        let cloudKit: String
        if backendBaseURL != nil {
            cloudKit = "disabled (backend mode)"
        } else if disableCloudKit {
            cloudKit = "disabled"
        } else {
            cloudKit = "enabled"
        }
        let backend = backendBaseURL?.absoluteString ?? "disabled"
        let workspace = backendWorkspaceSlug ?? "-"
        messages.append(
            "[Config] Mode: \(mode) | Ollama: \(ollamaModel) @ \(ollamaBaseURL.absoluteString) | Backend: \(backend) [workspace=\(workspace)] | Objective workers: \(objectiveWorkerConcurrency) | Webhook: \(webhookPort) | Clock: \(schedulerIntervalSeconds)s | CloudKit: \(cloudKit)"
        )
        if backendBaseURL != nil, (agentWebhookPublicURL == nil || agentWebhookPublicURL?.isEmpty == true) {
            messages.append(
                "[Config] AGENTKVT_AGENT_WEBHOOK_PUBLIC_URL is unset — registering http://127.0.0.1:\(webhookPort). Remote APIs cannot reach that address; set the env var to your Mac's reachable URL (e.g. Tailscale IP or tunnel) so Run now can dispatch tasks."
            )
        }
        if backendBaseURL == nil {
            messages.append(
                "[Config] WARNING: No AGENTKVT_API_BASE_URL. iPhone chat uses the server-backed queue; messages stay “Queued” until this runner is configured with the same API URL and AGENTKVT_AGENT_TOKEN as your backend (see group-container or ~/.agentkvt/agentkvt-runner.plist)."
            )
        }
        if agentMailEnabled {
            let inboxHint: String
            if let agentMailInboxId, !agentMailInboxId.isEmpty {
                inboxHint = agentMailInboxId
            } else if let agentMailUsername, !agentMailUsername.isEmpty {
                inboxHint = "\(agentMailUsername)@\(agentMailDomain ?? "agentmail.to")"
            } else {
                inboxHint = "auto-create"
            }
            messages.append(
                "[Config] AgentMail enabled | Inbox: \(inboxHint) | Poll: \(agentMailPollSeconds)s | Python: \(agentMailPythonExecutable)"
            )
        } else if imapEnabled {
            let username = imapUsername ?? "?"
            messages.append(
                "[Config] IMAP inbox polling enabled | Inbox: \(username) @ \(imapHost ?? "?") | Poll: \(imapPollSeconds)s"
            )
        }
        return messages
    }

    static func load(from source: RunnerSettingsSource = .live()) -> RunnerSettings {
        let configFileURL = resolveConfigFileURL(from: source)
        let fileLoad = loadConfigDictionary(at: configFileURL)
        let configValues = fileLoad.values ?? [:]
        let resolver = RunnerValueResolver(environment: source.environment, configValues: configValues)

        let runScheduler = resolver.bool(for: "RUN_SCHEDULER") ?? source.isAppBundle
        let schedulerIntervalSeconds = max(1, resolver.int(for: "SCHEDULER_INTERVAL_SECONDS") ?? 60)
        let objectiveWorkerConcurrency = min(8, max(1, resolver.int(for: "OBJECTIVE_WORKER_CONCURRENCY") ?? 3))
        let baseURLString = resolver.string(for: "OLLAMA_BASE_URL") ?? "http://localhost:11434"
        let ollamaBaseURL = URL(string: baseURLString) ?? URL(string: "http://localhost:11434")!
        let ollamaModel = resolver.string(for: "OLLAMA_MODEL") ?? "llama4:latest"
        let ollamaAPIKey = resolver.string(for: "OLLAMA_API_KEY")
        let geminiAPIKey = resolver.string(for: "GOOGLE_API_KEY")
        let backendBaseURL = resolver.string(for: "AGENTKVT_API_BASE_URL").flatMap(URL.init(string:))
        let backendWorkspaceSlug = resolver.string(for: "AGENTKVT_WORKSPACE_SLUG") ?? (backendBaseURL == nil ? nil : "default")
        let backendAgentToken = resolver.string(for: "AGENTKVT_AGENT_TOKEN")
        let notificationEmail = resolver.string(for: "NOTIFICATION_EMAIL")
        let agentMailAPIKey = resolver.string(for: "AGENTMAIL_API_KEY")
        let agentMailInboxId = resolver.string(for: "AGENTMAIL_INBOX_ID")
        let agentMailDisplayName = resolver.string(for: "AGENTMAIL_DISPLAY_NAME")
        let agentMailUsername = resolver.string(for: "AGENTMAIL_USERNAME")
        let agentMailDomain = resolver.string(for: "AGENTMAIL_DOMAIN")
        let agentMailInboxClientId = resolver.string(for: "AGENTMAIL_INBOX_CLIENT_ID")
        let agentMailPythonExecutable = resolver.string(for: "AGENTMAIL_PYTHON_EXECUTABLE") ?? "/usr/bin/python3"
        let agentMailPollSeconds = max(30, resolver.int(for: "AGENTMAIL_POLL_SECONDS") ?? 60)
        let githubPAT = resolver.string(for: "GITHUB_AGENT_PAT")
        let githubAllowedRepos = resolver.stringArray(for: "GITHUB_AGENT_REPOS")
        let inboxDirectory = resolver.expandedURL(for: "AGENTKVT_INBOX_DIR")
        let inboundDirectory = resolver.expandedURL(for: "AGENTKVT_INBOUND_DIR")
        let localFileAllowedDirectories = resolver.expandedURLArray(for: "AGENTKVT_LOCAL_FILE_DIRS")
        let configuredWebhookPort = resolver.int(for: "WEBHOOK_PORT") ?? 8765
        let webhookPort = UInt16(clamping: configuredWebhookPort)
        let agentWebhookPublicURL: String? = resolver.string(for: "AGENTKVT_AGENT_WEBHOOK_PUBLIC_URL").flatMap { raw in
            var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            while s.hasSuffix("/") { s.removeLast() }
            return s.isEmpty ? nil : s
        }
        let disableCloudKit = resolver.bool(for: "AGENTKVT_DISABLE_CLOUDKIT") ?? false
        let imapHost = resolver.string(for: "AGENTKVT_IMAP_HOST")
        let imapPort = resolver.int(for: "AGENTKVT_IMAP_PORT") ?? 993
        let imapUsername = resolver.string(for: "AGENTKVT_IMAP_USERNAME")
        let imapPassword = resolver.string(for: "AGENTKVT_IMAP_PASSWORD")
        let imapMailbox = resolver.string(for: "AGENTKVT_IMAP_MAILBOX") ?? "INBOX"
        let imapPollSeconds = max(60, resolver.int(for: "AGENTKVT_IMAP_POLL_SECONDS") ?? 300)

        return RunnerSettings(
            source: source,
            configFileURL: configFileURL,
            configFileLoaded: fileLoad.values != nil,
            configFileError: fileLoad.error,
            runScheduler: runScheduler,
            schedulerIntervalSeconds: schedulerIntervalSeconds,
            objectiveWorkerConcurrency: objectiveWorkerConcurrency,
            ollamaBaseURL: ollamaBaseURL,
            ollamaModel: ollamaModel,
            ollamaAPIKey: ollamaAPIKey,
            geminiAPIKey: geminiAPIKey,
            backendBaseURL: backendBaseURL,
            backendWorkspaceSlug: backendWorkspaceSlug,
            backendAgentToken: backendAgentToken,
            notificationEmail: notificationEmail,
            agentMailAPIKey: agentMailAPIKey,
            agentMailInboxId: agentMailInboxId,
            agentMailDisplayName: agentMailDisplayName,
            agentMailUsername: agentMailUsername,
            agentMailDomain: agentMailDomain,
            agentMailInboxClientId: agentMailInboxClientId,
            agentMailPythonExecutable: agentMailPythonExecutable,
            agentMailPollSeconds: agentMailPollSeconds,
            githubPAT: githubPAT,
            githubAllowedRepos: githubAllowedRepos,
            inboxDirectory: inboxDirectory,
            inboundDirectory: inboundDirectory,
            localFileAllowedDirectories: localFileAllowedDirectories,
            webhookPort: webhookPort,
            agentWebhookPublicURL: agentWebhookPublicURL,
            disableCloudKit: disableCloudKit,
            imapHost: imapHost,
            imapPort: imapPort,
            imapUsername: imapUsername,
            imapPassword: imapPassword,
            imapMailbox: imapMailbox,
            imapPollSeconds: imapPollSeconds
        )
    }

    private static func resolveConfigFileURL(from source: RunnerSettingsSource) -> URL {
        if let override = source.environment["AGENTKVT_CONFIG_FILE"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }

        if let groupContainerURL = source.groupContainerURL {
            return groupContainerURL
                .appending(path: "Library", directoryHint: .isDirectory)
                .appending(path: "Application Support", directoryHint: .isDirectory)
                .appending(path: "agentkvt-runner.plist", directoryHint: .notDirectory)
        }

        return source.homeDirectory
            .appending(path: ".agentkvt", directoryHint: .isDirectory)
            .appending(path: "agentkvt-runner.plist", directoryHint: .notDirectory)
    }

    private static func loadConfigDictionary(at url: URL) -> (values: [String: Any]?, error: String?) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (nil, nil)
        }

        do {
            let data = try Data(contentsOf: url)
            let raw = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let dictionary = raw as? [String: Any] else {
                return (nil, "root object must be a dictionary plist")
            }
            return (dictionary, nil)
        } catch {
            return (nil, String(describing: error))
        }
    }
}

private struct RunnerValueResolver {
    let environment: [String: String]
    let configValues: [String: Any]

    func string(for key: String) -> String? {
        if let value = environment[key], !value.isEmpty {
            return value
        }
        return string(from: configValues[key])
    }

    func int(for key: String) -> Int? {
        if let value = environment[key], let parsed = Int(value) {
            return parsed
        }
        return int(from: configValues[key])
    }

    func bool(for key: String) -> Bool? {
        if let value = environment[key], let parsed = parseBool(value) {
            return parsed
        }
        return bool(from: configValues[key])
    }

    func stringArray(for key: String) -> [String] {
        if let value = environment[key], !value.isEmpty {
            return splitList(value)
        }
        if let array = configValues[key] as? [String] {
            return array.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let string = string(from: configValues[key]) {
            return splitList(string)
        }
        return []
    }

    func expandedURL(for key: String) -> URL? {
        guard let path = string(for: key), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    func expandedURLArray(for key: String) -> [URL] {
        stringArray(for: key).compactMap { path in
            let expanded = (path as NSString).expandingTildeInPath
            return expanded.isEmpty ? nil : URL(fileURLWithPath: expanded)
        }
    }

    private func string(from value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func int(from value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private func bool(from value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return parseBool(string)
        default:
            return nil
        }
    }

    private func parseBool(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }

    private func splitList(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
