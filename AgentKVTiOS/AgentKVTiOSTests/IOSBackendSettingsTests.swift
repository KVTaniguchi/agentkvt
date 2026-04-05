import Foundation
import Testing
@testable import AgentKVTiOS

@Suite("IOSBackendSettings")
struct IOSBackendSettingsTests {

    @Test("isDirectOllamaConfigured is false without base URL or model")
    func notConfiguredWhenIncomplete() {
        let src = IOSBackendSettingsSource(
            environment: [:],
            groupContainerURL: nil
        )
        let s = IOSBackendSettings.load(from: src)
        #expect(s.ollamaBaseURL == nil)
        #expect(s.ollamaModel == nil)
        #expect(s.isDirectOllamaConfigured == false)
    }

    @Test("isDirectOllamaConfigured is true when AGENTKVT_OLLAMA_BASE_URL and AGENTKVT_OLLAMA_MODEL are set")
    func configuredWithAgentKVTKeys() {
        let src = IOSBackendSettingsSource(
            environment: [
                "AGENTKVT_OLLAMA_BASE_URL": "http://192.168.1.5:11434",
                "AGENTKVT_OLLAMA_MODEL": "llama3.2"
            ],
            groupContainerURL: nil
        )
        let s = IOSBackendSettings.load(from: src)
        #expect(s.ollamaBaseURL?.absoluteString == "http://192.168.1.5:11434")
        #expect(s.ollamaModel == "llama3.2")
        #expect(s.isDirectOllamaConfigured == true)
    }

    @Test("OLLAMA_BASE_URL and OLLAMA_MODEL work as fallbacks")
    func fallbackKeys() {
        let src = IOSBackendSettingsSource(
            environment: [
                "OLLAMA_BASE_URL": "http://10.0.0.2:11434",
                "OLLAMA_MODEL": "llama4"
            ],
            groupContainerURL: nil
        )
        let s = IOSBackendSettings.load(from: src)
        #expect(s.isDirectOllamaConfigured == true)
        #expect(s.ollamaModel == "llama4")
    }

    @Test("AGENTKVT_ keys take precedence over generic OLLAMA_ keys")
    func agentkvtPrecedence() {
        let src = IOSBackendSettingsSource(
            environment: [
                "AGENTKVT_OLLAMA_BASE_URL": "http://a:11434",
                "OLLAMA_BASE_URL": "http://b:11434",
                "AGENTKVT_OLLAMA_MODEL": "model-a",
                "OLLAMA_MODEL": "model-b"
            ],
            groupContainerURL: nil
        )
        let s = IOSBackendSettings.load(from: src)
        #expect(s.ollamaBaseURL?.absoluteString == "http://a:11434")
        #expect(s.ollamaModel == "model-a")
    }

    @Test("Whitespace-only model is not direct-Ollama configured")
    func whitespaceModelRejected() {
        let src = IOSBackendSettingsSource(
            environment: [
                "OLLAMA_BASE_URL": "http://127.0.0.1:11434",
                "OLLAMA_MODEL": "   "
            ],
            groupContainerURL: nil
        )
        let s = IOSBackendSettings.load(from: src)
        #expect(s.isDirectOllamaConfigured == false)
    }

    @Test("startupMessage mentions direct Ollama when configured")
    func startupMessageIncludesOllama() {
        let src = IOSBackendSettingsSource(
            environment: [
                "AGENTKVT_API_BASE_URL": "https://api.example.com",
                "AGENTKVT_WORKSPACE_SLUG": "ws1",
                "AGENTKVT_OLLAMA_BASE_URL": "http://mac.local:11434",
                "AGENTKVT_OLLAMA_MODEL": "m1"
            ],
            groupContainerURL: nil
        )
        let s = IOSBackendSettings.load(from: src)
        #expect(s.startupMessage.contains("direct Ollama"))
        #expect(s.startupMessage.contains("m1"))
        #expect(s.startupMessage.contains("mac.local"))
    }
}

@Suite("RootViewStateResolver")
struct RootViewStateResolverTests {

    @Test("shows backend error when bootstrap fails before any local family members exist")
    func showsBackendErrorWhenNoMembersExist() {
        let destination = RootViewStateResolver.destination(
            isBackendEnabled: true,
            bootstrapState: .failed("Could not connect"),
            memberCount: 0,
            hasValidSelection: false
        )

        #expect(destination == .backendError("Could not connect"))
    }

    @Test("keeps existing members reachable even if bootstrap refresh fails")
    func keepsExistingMembersReachableAfterBootstrapFailure() {
        let destination = RootViewStateResolver.destination(
            isBackendEnabled: true,
            bootstrapState: .failed("Could not connect"),
            memberCount: 2,
            hasValidSelection: false
        )

        #expect(destination == .profilePicker)
    }

    @Test("shows onboarding only when there are no members and no bootstrap failure")
    func showsOnboardingForEmptyLocalState() {
        let destination = RootViewStateResolver.destination(
            isBackendEnabled: false,
            bootstrapState: .loaded,
            memberCount: 0,
            hasValidSelection: false
        )

        #expect(destination == .onboarding)
    }

    @Test("shows dashboard when a valid profile is already selected")
    func showsDashboardForValidSelection() {
        let destination = RootViewStateResolver.destination(
            isBackendEnabled: true,
            bootstrapState: .loaded,
            memberCount: 1,
            hasValidSelection: true
        )

        #expect(destination == .dashboard)
    }
}
