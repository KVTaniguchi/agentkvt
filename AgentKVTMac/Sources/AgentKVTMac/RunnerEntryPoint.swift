import CloudKit
import Foundation
import ManagerCore
import SwiftData

/// Shared CloudKit container used by both iOS and Mac app for SwiftData sync.
public let cloudKitContainerIdentifier = "iCloud.AgentKVT"
public let sharedAppGroupIdentifier = "group.com.agentkvt.shared"

/// Runs the AgentKVT Mac runner (scheduler or single test). Use from the CLI executable or from the Mac app target.
/// When run from an app that has the iCloud.AgentKVT entitlement, SwiftData will use the shared CloudKit container.
public func runAgentKVTMacRunner() async {
    let settings = RunnerSettings.load()
    for message in settings.startupMessages {
        print(message)
    }
    let shouldAttemptCloudKit = !settings.disableCloudKit && settings.isAppBundle && settings.backendBaseURL == nil
    if shouldAttemptCloudKit {
        logMacCloudKitDiagnostics()
    } else {
        print("[CloudKitDiagnostics] Skipped (CloudKit disabled or unavailable for this process mode).")
    }

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
    registry.register(makeWebSearchAndFetchTool(apiKey: settings.ollamaAPIKey))
    registry.register(makeHeadlessBrowserScoutTool())
    registry.register(makeFetchBeeAIContextTool(modelContext: context))
    if let email = settings.notificationEmail, !email.isEmpty {
        registry.register(makeSendNotificationEmailTool(destinationEmail: email))
    }
    registry.register(makeGetLifeContextTool(modelContext: context))
    if let pat = settings.githubPAT, !pat.isEmpty {
        let repos = settings.githubAllowedRepos
        if !repos.isEmpty {
            registry.register(makeGitHubTool(pat: pat, allowedRepos: repos))
        }
    }
    let inboxDir: URL
    if let configuredInboxDir = settings.inboxDirectory {
        inboxDir = configuredInboxDir
    } else {
        inboxDir = EmailIngestor.defaultInboxDirectory
    }
    let emailIngestor = EmailIngestor(directory: inboxDir)
    registry.register(makeIncomingEmailTriggerTool(ingestor: emailIngestor))

    let dropzoneDir: URL
    if let configuredDropzoneDir = settings.inboundDirectory {
        dropzoneDir = configuredDropzoneDir
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

    registry.register(makeReadResearchSnapshotTool(modelContext: context))
    registry.register(makeWriteResearchSnapshotTool(modelContext: context))
    registry.register(makeMultiStepSearchTool(apiKey: settings.ollamaAPIKey))

    let client = OllamaClient(
        baseURL: settings.ollamaBaseURL,
        model: settings.ollamaModel
    )
    let backendClient = settings.backendBaseURL.map {
        BackendAPIClient(
            baseURL: $0,
            workspaceSlug: settings.backendWorkspaceSlug ?? "default",
            agentToken: settings.backendAgentToken
        )
    }

    if settings.runScheduler {
        if let backendClient {
            registry.register(makeWriteActionItemTool(backendClient: backendClient))
            registry.register(makeFetchAgentLogsTool(backendClient: backendClient))
            registry.register(makeReadObjectiveSnapshotTool(backendClient: backendClient))
            registry.register(makeWriteObjectiveSnapshotTool(backendClient: backendClient))
        } else {
            registry.register(makeWriteActionItemTool(modelContext: context))
            registry.register(makeFetchAgentLogsTool(modelContext: context))
        }
        await runScheduler(
            context: sharedModelContext,
            modelContainer: container,
            client: client,
            registry: registry,
            backendClient: backendClient,
            emailIngestor: emailIngestor,
            dropzoneDir: dropzoneDir,
            webhookPort: settings.webhookPort,
            clockIntervalSeconds: settings.schedulerIntervalSeconds,
            settings: settings
        )
    } else {
        if let backendClient {
            registry.register(makeWriteActionItemTool(backendClient: backendClient))
            registry.register(makeFetchAgentLogsTool(backendClient: backendClient))
        } else {
            registry.register(makeWriteActionItemTool(modelContext: context))
            registry.register(makeFetchAgentLogsTool(modelContext: context))
        }
        await runSingleTest(registry: registry, client: client)
    }
}

private func logMacCloudKitDiagnostics() {
    let container = CKContainer(identifier: cloudKitContainerIdentifier)
    print("[CloudKitDiagnostics] Container: \(cloudKitContainerIdentifier)")
    container.accountStatus { status, error in
        if let error {
            print("[CloudKitDiagnostics] accountStatus error: \(error)")
            return
        }
        print("[CloudKitDiagnostics] accountStatus: \(describeCloudKitAccountStatus(status))")
    }
    container.fetchUserRecordID { recordID, error in
        if let error {
            print("[CloudKitDiagnostics] userRecordID error: \(error)")
            return
        }
        guard let recordID else {
            print("[CloudKitDiagnostics] userRecordID: nil")
            return
        }
        print("[CloudKitDiagnostics] userRecordID: \(recordID.recordName) zone=\(recordID.zoneID.zoneName)")
    }
}

private func describeCloudKitAccountStatus(_ status: CKAccountStatus) -> String {
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
    modelContainer: ModelContainer,
    client: OllamaClient,
    registry: ToolRegistry,
    backendClient: BackendAPIClient?,
    emailIngestor: EmailIngestor,
    dropzoneDir: URL,
    webhookPort: UInt16,
    clockIntervalSeconds: Int,
    settings: RunnerSettings
) async {
    // ── Build the strict serial execution queue ──────────────────────────────────
    // All triggers funnel here. The actor's `run()` loop processes them one at a
    // time: while the LLM is awaiting a response, new triggers buffer in AgentQueue
    // (priority-sorted, bounded at 64 items) and are drained after inference completes.
    let executionQueue = AgentExecutionQueue(
        modelContext: context,
        modelContainer: modelContainer,
        client: client,
        registry: registry,
        backendClient: backendClient,
        emailIngestor: emailIngestor,
        dropzoneDir: dropzoneDir,
        objectiveWorkerConcurrency: settings.objectiveWorkerConcurrency
    )

    // Ensure directories exist before starting watchers.
    DropzoneService(directory: dropzoneDir).ensureDirectory()
    emailIngestor.ensureDirectory()

    // ── IMAP poller (optional — only when credentials are configured) ────────────
    if settings.imapEnabled {
        let imapPoller = IMAPEmailPoller(settings: settings, inboxDir: emailIngestor.directory)
        await imapPoller.start()
    }

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
    let webhookListener = WebhookListener(port: webhookPort) { payload in
        if WebhookChatSignal.matches(payload) {
            executionQueue.enqueue(.processPendingChat, priority: .high)
        } else {
            executionQueue.enqueue(.webhook(payload), priority: .high)
        }
    }
    webhookListener.start()

    if backendClient == nil {
        // ── CloudKit observer (reactive iOS→Mac bridge) ──────────────────────────
        // Fires on any remote SwiftData change (chat messages, IncomingEmailSummary, etc.).
        // High priority so pending chat is processed promptly instead of waiting behind the
        // clock tick. No ModelContext access here — work runs in dispatch(.cloudKitSync).
        let cloudKitObserver = CloudKitObserver {
            executionQueue.enqueue(.cloudKitSync, priority: .high)
        }
        cloudKitObserver.start()
    }

    // ── 60-second clock (lowest priority — background heartbeat) ─────────────────
    // Checks due CRON missions and pending chat messages. Arrives last in line when
    // a webhook or CloudKit sync is already queued.
    let clockTimer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    clockTimer.schedule(deadline: .now(), repeating: .seconds(clockIntervalSeconds))
    clockTimer.setEventHandler {
        executionQueue.enqueue(.clockTick, priority: .low)
    }
    clockTimer.resume()

    // Off-LAN: iOS POSTs `/v1/chat_wake` to the deployed API. The agent calls the long-poll
    // endpoint which blocks on a Postgres NOTIFY for up to 30s — events arrive sub-100ms
    // on a real wake, 30s on silence. No sleep loop needed.
    if let backendClient {
        Task(priority: .utility) {
            while !Task.isCancelled {
                do {
                    let pending = try await backendClient.consumeChatWakeBlocking()
                    if pending {
                        executionQueue.enqueue(.processPendingChat, priority: .high)
                    }
                } catch {
                    print("[Scheduler] chat_wake long-poll failed: \(error)")
                    // Brief back-off on error to avoid hammering the server on repeated failures.
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }

        // Agent registration + heartbeat: registers capabilities on startup, then heartbeats
        // every 15s so TaskExecutorJob can route tasks to this agent by capability.
        let agentId = "mac-agent-\(webhookPort)"
        let webhookURLString = "http://127.0.0.1:\(webhookPort)"
        var agentCapabilities = [
            "web_search", "file_read", "objective_research",
            "write_action_item", "life_context", "work_units"
        ]
        if settings.notificationEmail != nil { agentCapabilities.append("email") }
        if settings.githubPAT != nil { agentCapabilities.append("github") }

        Task(priority: .utility) {
            while !Task.isCancelled {
                do {
                    try await backendClient.registerAgent(
                        agentId: agentId,
                        capabilities: agentCapabilities,
                        webhookURL: webhookURLString
                    )
                } catch {
                    print("[Scheduler] agent registration failed: \(error)")
                }
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    print("""
        [Scheduler] Event-driven scheduler started.
          Inbox:    \(emailIngestor.directory.path)
          Inbound:  \(dropzoneDir.path)
          Webhook:  port \(webhookPort) (chat wake: POST JSON {"agentkvt":"process_chat"})
          Clock:    every \(clockIntervalSeconds)s
          CloudKit: \(backendClient == nil ? "listening for NSPersistentStoreRemoteChangeNotification" : "disabled (backend mode)")
        """)
    if backendClient != nil {
        print("  Remote:   backend chat queue, chat_wake long-poll, and inbound-file sync enabled")
    }

    // ── Run forever — drain loop blocks (async suspends) until the process exits ──
    await executionQueue.run()
}
