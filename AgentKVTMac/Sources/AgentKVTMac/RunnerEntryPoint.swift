import Foundation
import ManagerCore
import SwiftData

/// Shared CloudKit container used by both iOS and Mac app for SwiftData sync.
public let cloudKitContainerIdentifier = "iCloud.AgentKVT"
public let sharedAppGroupIdentifier = "group.com.agentkvt.shared"

/// Runs the AgentKVT Mac runner (scheduler or single test). Use from the CLI executable or from the Mac app target.
/// When run from an app that has the iCloud.AgentKVT entitlement, SwiftData will use the shared CloudKit container.
public func runAgentKVTMacRunner() async {
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
    var container: ModelContainer?
    let sharedPersistentConfig = ModelConfiguration(
        "default",
        schema: schema,
        isStoredInMemoryOnly: false,
        allowsSave: true,
        groupContainer: .identifier(sharedAppGroupIdentifier),
        cloudKitDatabase: .private(cloudKitContainerIdentifier)
    )
    let cloudKitOnlyConfig = ModelConfiguration(
        "default-cloudkit",
        schema: schema,
        isStoredInMemoryOnly: false,
        allowsSave: true,
        groupContainer: .none,
        cloudKitDatabase: .private(cloudKitContainerIdentifier)
    )
    let localPersistentConfig = ModelConfiguration(
        "default-local",
        schema: schema,
        isStoredInMemoryOnly: false,
        allowsSave: true
    )
    let environment = ProcessInfo.processInfo.environment
    let bundleIdentifier = Bundle.main.bundleIdentifier
    let shouldAttemptCloudKit = environment["AGENTKVT_DISABLE_CLOUDKIT"] != "1"
        && !(bundleIdentifier?.isEmpty ?? true)

    if shouldAttemptCloudKit,
       let c = try? ModelContainer(for: schema, configurations: [sharedPersistentConfig]) {
        container = c
        print("SwiftData storage: app group + CloudKit")
    } else if shouldAttemptCloudKit,
              let c = try? ModelContainer(for: schema, configurations: [cloudKitOnlyConfig]) {
        container = c
        print("SwiftData storage: CloudKit only")
    } else if let c = try? ModelContainer(for: schema, configurations: [localPersistentConfig]) {
        container = c
        if shouldAttemptCloudKit {
            print("SwiftData storage: local disk fallback")
        } else {
            print("SwiftData storage: local disk only (CloudKit disabled for CLI runner)")
        }
    } else {
        let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try? ModelContainer(for: schema, configurations: [inMemoryConfig])
        print("SwiftData storage: in-memory fallback")
    }
    guard let container else {
        print("Failed to create ModelContainer")
        exit(1)
    }
    let context = ModelContext(container)
    let sharedModelContext = SharedModelContext(context)
    let registry = ToolRegistry()
    registry.register(makeWriteActionItemTool(modelContext: context))
    registry.register(makeWebSearchAndFetchTool())
    registry.register(makeHeadlessBrowserScoutTool())
    registry.register(makeFetchBeeAIContextTool(modelContext: context))
    if let email = ProcessInfo.processInfo.environment["NOTIFICATION_EMAIL"], !email.isEmpty {
        registry.register(makeSendNotificationEmailTool(destinationEmail: email))
    }
    registry.register(makeGetLifeContextTool(modelContext: context))
    registry.register(makeFetchMissionStatusTool(modelContext: context))
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

    let dropzoneDir: URL
    if let path = ProcessInfo.processInfo.environment["AGENTKVT_INBOUND_DIR"], !path.isEmpty {
        dropzoneDir = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    } else {
        dropzoneDir = DropzoneService.defaultDirectory
    }
    registry.register(makeListDropzoneFilesTool(directory: dropzoneDir))
    registry.register(makeReadDropzoneFileTool(directory: dropzoneDir))

    // iOS edge-processing bridge: read pre-summarized emails that arrived via CloudKit.
    registry.register(makeFetchEmailSummariesTool(modelContext: context))
    registry.register(makeMarkEmailSummaryProcessedTool(modelContext: context))

    registry.register(makeFetchWorkUnitsTool(modelContext: context))
    registry.register(makeUpdateWorkUnitTool(modelContext: context))
    registry.register(makePinEphemeralNoteTool(modelContext: context))
    registry.register(makeListResourceHealthTool(modelContext: context))
    registry.register(makeReportResourceFailureTool(modelContext: context))
    registry.register(makeClearResourceHealthTool(modelContext: context))

    let client = OllamaClient(
        baseURL: URL(string: ProcessInfo.processInfo.environment["OLLAMA_BASE_URL"] ?? "http://localhost:11434")!,
        model: ProcessInfo.processInfo.environment["OLLAMA_MODEL"] ?? "llama3.2"
    )

    if ProcessInfo.processInfo.environment["RUN_SCHEDULER"] == "1" {
        await runScheduler(
            context: sharedModelContext,
            client: client,
            registry: registry,
            emailIngestor: emailIngestor,
            dropzoneDir: dropzoneDir
        )
    } else {
        await runSingleTest(registry: registry, client: client)
    }
}

// MARK: - Single test run (dev / smoke test)

private func runSingleTest(registry: ToolRegistry, client: OllamaClient) async {
    let allowedTools = ["write_action_item"]
    let loop = AgentLoop(client: client, registry: registry, allowedToolIds: allowedTools)
    let systemPrompt = """
    You are a helpful assistant. When the user asks you to create an action for them, you must call the write_action_item tool exactly once.
    Use one of these valid systemIntent values only: calendar.create, mail.reply, reminder.add, url.open.
    """
    let userMessage = """
    Create one action item with title "Test Action from Runner" and systemIntent "url.open".
    Do not explain anything before or after the tool call.
    """
    do {
        let result = try await loop.run(systemPrompt: systemPrompt, userMessage: userMessage)
        print("Agent result: \(result)")
    } catch {
        print("Error: \(error)")
        exit(1)
    }
}

// MARK: - Scheduler (production event-driven mode)

private func runScheduler(
    context: SharedModelContext,
    client: OllamaClient,
    registry: ToolRegistry,
    emailIngestor: EmailIngestor,
    dropzoneDir: URL
) async {
    // ── Build the strict serial execution queue ──────────────────────────────────
    // All triggers funnel here. The actor's `run()` loop processes them one at a
    // time: while the LLM is awaiting a response, new triggers buffer in AgentQueue
    // (priority-sorted, bounded at 64 items) and are drained after inference completes.
    let executionQueue = MissionExecutionQueue(
        modelContext: context,
        client: client,
        registry: registry,
        emailIngestor: emailIngestor,
        dropzoneDir: dropzoneDir
    )

    // Ensure directories exist before starting watchers.
    DropzoneService(directory: dropzoneDir).ensureDirectory()
    emailIngestor.ensureDirectory()

    // ── FSEvents: inbox (.eml files) ─────────────────────────────────────────────
    let inboxWatcher = DirectoryWatcher(directory: emailIngestor.directory) { url in
        guard url.pathExtension.lowercased() == "eml" else { return }
        executionQueue.enqueue(.emailFile(url), priority: .normal)
    }

    // ── FSEvents: inbound dropzone ───────────────────────────────────────────────
    let inboundWatcher = DirectoryWatcher(directory: dropzoneDir) { url in
        executionQueue.enqueue(.inboundFile(url), priority: .normal)
    }

    do {
        try inboxWatcher.start()
        try inboundWatcher.start()
    } catch {
        print("DirectoryWatcher failed to start: \(error). Continuing without file-system events.")
    }

    // ── Webhook listener (highest priority — explicit external intent) ────────────
    let webhookPort = UInt16(ProcessInfo.processInfo.environment["WEBHOOK_PORT"] ?? "8765") ?? 8765
    let webhookListener = WebhookListener(port: webhookPort) { payload in
        executionQueue.enqueue(.webhook(payload), priority: .high)
    }
    webhookListener.start()

    // ── CloudKit observer (reactive iOS→Mac bridge) ──────────────────────────────
    // Fires when CloudKit delivers IncomingEmailSummary records inserted by the
    // iPhone's EdgeSummarizationService. No ModelContext access here — the fetch
    // happens inside MissionExecutionQueue.dispatch(.cloudKitSync) on the actor's
    // serial executor.
    let cloudKitObserver = CloudKitObserver {
        executionQueue.enqueue(.cloudKitSync, priority: .normal)
    }
    cloudKitObserver.start()

    // ── 60-second clock (lowest priority — background heartbeat) ─────────────────
    // Checks due CRON missions and pending chat messages. Arrives last in line when
    // a webhook or CloudKit sync is already queued.
    let clockTimer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    clockTimer.schedule(deadline: .now(), repeating: .seconds(60))
    clockTimer.setEventHandler {
        executionQueue.enqueue(.clockTick, priority: .low)
    }
    clockTimer.resume()

    print("""
        [Scheduler] Event-driven scheduler started.
          Inbox:    \(emailIngestor.directory.path)
          Inbound:  \(dropzoneDir.path)
          Webhook:  port \(webhookPort)
          CloudKit: listening for NSPersistentStoreRemoteChangeNotification
        """)

    // ── Run forever — drain loop blocks (async suspends) until the process exits ──
    await executionQueue.run()
}
