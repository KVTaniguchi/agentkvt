import Foundation
import Testing
@testable import AgentKVTMac

struct RunnerSettingsTests {

    @Test("app bundles default to scheduler mode")
    func appBundleDefaultsToSchedulerMode() {
        let source = RunnerSettingsSource(
            environment: [:],
            bundleIdentifier: "com.agentkvt.app",
            groupContainerURL: nil,
            homeDirectory: URL(fileURLWithPath: "/tmp/agentkvt-runner-settings-home")
        )

        let settings = RunnerSettings.load(from: source)

        #expect(settings.runScheduler)
        #expect(settings.ollamaModel == "llama4:latest")
        #expect(settings.webhookPort == 8765)
        #expect(settings.agentWebhookPublicURL == nil)
        #expect(settings.schedulerIntervalSeconds == 60)
        #expect(settings.configFileURL.path == "/tmp/agentkvt-runner-settings-home/.agentkvt/agentkvt-runner.plist")
    }

    @Test("config file supplies production app settings")
    func configFileSuppliesSettings() throws {
        let tempDirectory = makeTemporaryDirectory()
        let groupContainer = tempDirectory.appending(path: "group", directoryHint: .isDirectory)
        let appSupportDirectory = groupContainer
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)

        let configFile = appSupportDirectory.appending(path: "agentkvt-runner.plist", directoryHint: .notDirectory)
        let plist: [String: Any] = [
            "RUN_SCHEDULER": false,
            "OLLAMA_MODEL": "llama3.2:latest",
            "OLLAMA_BASE_URL": "http://127.0.0.1:11434",
            "OLLAMA_API_KEY": "ollama-test-key",
            "AGENTKVT_API_BASE_URL": "http://127.0.0.1:3000",
            "AGENTKVT_WORKSPACE_SLUG": "family",
            "AGENTKVT_AGENT_TOKEN": "secret-token",
            "SCHEDULER_INTERVAL_SECONDS": 15,
            "WEBHOOK_PORT": 9001
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: configFile)

        let source = RunnerSettingsSource(
            environment: [:],
            bundleIdentifier: "com.agentkvt.app",
            groupContainerURL: groupContainer,
            homeDirectory: tempDirectory
        )

        let settings = RunnerSettings.load(from: source)

        #expect(settings.configFileLoaded)
        #expect(settings.runScheduler == false)
        #expect(settings.ollamaModel == "llama3.2:latest")
        #expect(settings.ollamaBaseURL.absoluteString == "http://127.0.0.1:11434")
        #expect(settings.ollamaAPIKey == "ollama-test-key")
        #expect(settings.backendBaseURL?.absoluteString == "http://127.0.0.1:3000")
        #expect(settings.backendWorkspaceSlug == "family")
        #expect(settings.backendAgentToken == "secret-token")
        #expect(settings.schedulerIntervalSeconds == 15)
        #expect(settings.webhookPort == 9001)
    }

    @Test("environment overrides config file")
    func environmentOverridesConfigFile() throws {
        let tempDirectory = makeTemporaryDirectory()
        let configFile = tempDirectory.appending(path: "runner.plist", directoryHint: .notDirectory)
        let plist: [String: Any] = [
            "RUN_SCHEDULER": false,
            "OLLAMA_MODEL": "llama4:latest",
            "OLLAMA_API_KEY": "config-key",
            "SCHEDULER_INTERVAL_SECONDS": 45
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: configFile)

        let source = RunnerSettingsSource(
            environment: [
                "AGENTKVT_CONFIG_FILE": configFile.path,
                "RUN_SCHEDULER": "1",
                "OLLAMA_MODEL": "llama3.2:latest",
                "OLLAMA_API_KEY": "env-key",
                "SCHEDULER_INTERVAL_SECONDS": "10",
                "AGENTKVT_API_BASE_URL": "http://127.0.0.1:3000",
                "AGENTKVT_WORKSPACE_SLUG": "override-workspace"
            ],
            bundleIdentifier: "com.agentkvt.app",
            groupContainerURL: nil,
            homeDirectory: tempDirectory
        )

        let settings = RunnerSettings.load(from: source)

        #expect(settings.runScheduler)
        #expect(settings.ollamaModel == "llama3.2:latest")
        #expect(settings.ollamaAPIKey == "env-key")
        #expect(settings.schedulerIntervalSeconds == 10)
        #expect(settings.backendBaseURL?.absoluteString == "http://127.0.0.1:3000")
        #expect(settings.backendWorkspaceSlug == "override-workspace")
    }

    @Test("AGENTKVT_AGENT_WEBHOOK_PUBLIC_URL trims trailing slashes")
    func agentWebhookPublicURLFromEnvironment() {
        let source = RunnerSettingsSource(
            environment: [
                "AGENTKVT_AGENT_WEBHOOK_PUBLIC_URL": "http://10.0.0.5:8765///",
                "AGENTKVT_API_BASE_URL": "http://127.0.0.1:3000"
            ],
            bundleIdentifier: "com.agentkvt.app",
            groupContainerURL: nil,
            homeDirectory: URL(fileURLWithPath: "/tmp/agentkvt-runner-settings-home")
        )
        let settings = RunnerSettings.load(from: source)
        #expect(settings.agentWebhookPublicURL == "http://10.0.0.5:8765")
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
