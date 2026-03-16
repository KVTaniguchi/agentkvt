import Foundation
import ManagerCore
import SwiftData

/// Shared CloudKit container used by both iOS and Mac app for SwiftData sync.
public let cloudKitContainerIdentifier = "iCloud.AgentKVT"

/// Runs the AgentKVT Mac runner (scheduler or single test). Use from the CLI executable or from the Mac app target.
/// When run from an app that has the iCloud.AgentKVT entitlement, SwiftData will use the shared CloudKit container.
public func runAgentKVTMacRunner() async {
    let schema = Schema([
        LifeContext.self,
        MissionDefinition.self,
        ActionItem.self,
        AgentLog.self,
        InboundFile.self,
    ])
    var container: ModelContainer?
    let persistentConfig = ModelConfiguration(
        "default",
        schema: schema,
        isStoredInMemoryOnly: false,
        allowsSave: true,
        groupContainer: .none,
        cloudKitDatabase: .private(cloudKitContainerIdentifier)
    )
    if let c = try? ModelContainer(for: schema, configurations: [persistentConfig]) {
        container = c
    } else {
        let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try? ModelContainer(for: schema, configurations: [inMemoryConfig])
    }
    guard let container else {
        print("Failed to create ModelContainer")
        exit(1)
    }
    let context = ModelContext(container)
    let registry = ToolRegistry()
    registry.register(makeWriteActionItemTool(modelContext: context))
    registry.register(makeWebSearchAndFetchTool())
    registry.register(makeHeadlessBrowserScoutTool())
    registry.register(makeFetchBeeAIContextTool(modelContext: context))
    if let email = ProcessInfo.processInfo.environment["NOTIFICATION_EMAIL"], !email.isEmpty {
        registry.register(makeSendNotificationEmailTool(destinationEmail: email))
    }
    if let pat = ProcessInfo.processInfo.environment["GITHUB_AGENT_PAT"],
       let reposEnv = ProcessInfo.processInfo.environment["GITHUB_AGENT_REPOS"], !pat.isEmpty {
        let repos = reposEnv.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !repos.isEmpty {
            registry.register(makeGitHubTool(pat: pat, allowedRepos: repos))
        }
    }
    let inboxDir: URL
    if let path = ProcessInfo.processInfo.environment["AGENTKVT_INBOX_DIR"], !path.isEmpty {
        inboxDir = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    } else {
        inboxDir = EmailIngestor.defaultInboxDirectory
    }
    let emailIngestor = EmailIngestor(directory: inboxDir)
    registry.register(makeIncomingEmailTriggerTool(ingestor: emailIngestor))

    let client = OllamaClient(
        baseURL: URL(string: ProcessInfo.processInfo.environment["OLLAMA_BASE_URL"] ?? "http://localhost:11434")!,
        model: ProcessInfo.processInfo.environment["OLLAMA_MODEL"] ?? "llama3.2"
    )

    if ProcessInfo.processInfo.environment["RUN_SCHEDULER"] == "1" {
        await runScheduler(context: context, client: client, registry: registry, emailIngestor: emailIngestor)
    } else {
        await runSingleTest(registry: registry, client: client)
    }
}

private func runSingleTest(registry: ToolRegistry, client: OllamaClient) async {
    let allowedTools = ["write_action_item"]
    let loop = AgentLoop(client: client, registry: registry, allowedToolIds: allowedTools)
    let systemPrompt = "You are a helpful assistant. When the user asks you to create an action for them, use the write_action_item tool with a short title and systemIntent. You must use the tool when asked to create or write an action."
    let userMessage = "Create one action item with title 'Test Action from Runner' and systemIntent 'test.intent'."
    do {
        let result = try await loop.run(systemPrompt: systemPrompt, userMessage: userMessage)
        print("Agent result: \(result)")
    } catch {
        print("Error: \(error)")
        exit(1)
    }
}

private func runScheduler(context: ModelContext, client: OllamaClient, registry: ToolRegistry, emailIngestor: EmailIngestor) async {
    let scheduler = MissionScheduler()
    let runner = MissionRunner(modelContext: context, client: client, registry: registry)
    let intervalSeconds = Int(ProcessInfo.processInfo.environment["SCHEDULER_INTERVAL_SECONDS"] ?? "300") ?? 300
    let dropzoneDir: URL
    if let path = ProcessInfo.processInfo.environment["AGENTKVT_INBOUND_DIR"], !path.isEmpty {
        dropzoneDir = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    } else {
        dropzoneDir = DropzoneService.defaultDirectory
    }
    let dropzone = DropzoneService(directory: dropzoneDir)
    let cloudInbound = CloudInboundService(modelContext: context, directory: dropzoneDir)
    dropzone.ensureDirectory()
    dropzone.startWatching()
    emailIngestor.ensureDirectory()
    emailIngestor.startWatching()
    print("Scheduler started; checking every \(intervalSeconds)s. Dropzone: \(dropzoneDir.path). Inbox: \(emailIngestor.directory.path)")
    while true {
        do {
            cloudInbound.syncInboundFiles()
            let descriptor = FetchDescriptor<MissionDefinition>()
            let missions = try context.fetch(descriptor)
            let due = scheduler.dueMissions(from: missions)
            let inboundContext = dropzone.getContent()
            for mission in due {
                do {
                    try await runner.run(mission, additionalContext: inboundContext.isEmpty ? nil : inboundContext)
                    print("Ran mission: \(mission.missionName)")
                } catch {
                    print("Mission \(mission.missionName) failed: \(error)")
                }
            }
        } catch {
            print("Fetch missions error: \(error)")
        }
        try? await Task.sleep(nanoseconds: UInt64(intervalSeconds) * 1_000_000_000)
    }
}
