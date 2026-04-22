import Foundation
import ManagerCore
import SwiftData


public let sharedAppGroupIdentifier = "group.com.agentkvt.shared"

/// Runs the AgentKVT Mac runner (scheduler or single test). Use from the CLI executable or from the Mac app target.
/// When run from an app that has the iCloud.AgentKVT entitlement, SwiftData will use the shared CloudKit container.
public func runAgentKVTMacRunner() async {
    let settings = RunnerSettings.load()
    for message in settings.startupMessages {
        print(message)
    }


    let schema = Schema([
        LifeContext.self,
        AgentLog.self,
        InboundFile.self,
        ChatThread.self,
        ChatMessage.self,

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
        groupContainer: .identifier(sharedAppGroupIdentifier)
    )
    let localPersistentConfig = ModelConfiguration(
        "default-local",
        schema: schema,
        isStoredInMemoryOnly: false,
        allowsSave: true
    )
    let preferLocalPersistentStore = settings.disableCloudKit || settings.backendBaseURL != nil
    let persistentConfigurations = preferLocalPersistentStore
        ? [(localPersistentConfig, "local disk"), (sharedPersistentConfig, "app group local disk")]
        : [(sharedPersistentConfig, "app group local disk"), (localPersistentConfig, "local disk fallback")]

    for (configuration, label) in persistentConfigurations {
        if let c = try? ModelContainer(for: schema, configurations: [configuration]) {
            container = c
            print("SwiftData storage: \(label)")
            break
        }
    }

    if container == nil {
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
    let inboxDir: URL
    if let configuredInboxDir = settings.inboxDirectory {
        inboxDir = configuredInboxDir
    } else {
        inboxDir = EmailIngestor.defaultInboxDirectory
    }
    let agentMailBridge = settings.agentMailEnabled ? AgentMailBridge(settings: settings, inboxDir: inboxDir) : nil
    if let email = settings.notificationEmail, !email.isEmpty {
        if let agentMailBridge {
            registry.register(
                makeSendNotificationEmailTool(
                    destinationEmail: email,
                    sendVia: .agentMail(client: agentMailBridge)
                )
            )
        } else {
            registry.register(makeSendNotificationEmailTool(destinationEmail: email))
        }
    }
    registry.register(makeGetLifeContextTool(modelContext: context))
    if let pat = settings.githubPAT, !pat.isEmpty {
        let repos = settings.githubAllowedRepos
        if !repos.isEmpty {
            registry.register(makeGitHubTool(pat: pat, allowedRepos: repos))
        }
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



    registry.register(makeFetchWorkUnitsTool(modelContext: context))
    registry.register(makeUpdateWorkUnitTool(modelContext: context))
    registry.register(makePinEphemeralNoteTool(modelContext: context))
    registry.register(makeListResourceHealthTool(modelContext: context))
    registry.register(makeReportResourceFailureTool(modelContext: context))
    registry.register(makeClearResourceHealthTool(modelContext: context))

    registry.register(makeReadResearchSnapshotTool(modelContext: context))
    registry.register(makeWriteResearchSnapshotTool(modelContext: context))
    registry.register(makeMultiStepSearchTool(apiKey: settings.ollamaAPIKey))
    if let geminiKey = settings.geminiAPIKey, !geminiKey.isEmpty {
        registry.register(makeGeminiAskTool(apiKey: geminiKey))
    }

    if !settings.localFileAllowedDirectories.isEmpty {
        registry.register(makeReadLocalFileTool(allowedDirectories: settings.localFileAllowedDirectories))
    }
    registry.register(makeReadCalendarTool())
    registry.register(makeWriteReminderTool())
    registry.register(makeShellCommandTool())
    registry.register(makePlaywrightScoutTool())

    let primaryClient = OllamaClient(
        baseURL: settings.ollamaBaseURL,
        model: settings.ollamaModel
    )
    let client: any OllamaClientProtocol
    if let geminiKey = settings.geminiAPIKey, !geminiKey.isEmpty {
        client = FallbackOllamaClient(
            primary: primaryClient,
            fallback: GeminiOllamaAdapter(apiKey: geminiKey)
        )
    } else {
        client = primaryClient
    }
    let backendClient = settings.backendBaseURL.map {
        BackendAPIClient(
            baseURL: $0,
            workspaceSlug: settings.backendWorkspaceSlug ?? "default",
            agentToken: settings.backendAgentToken
        )
    }

    if settings.runScheduler {
        if let backendClient {
            registry.register(makeFetchAgentLogsTool(backendClient: backendClient))
            registry.register(makeFetchAgentLogDigestTool(backendClient: backendClient))
            registry.register(makeReadObjectiveSnapshotTool(backendClient: backendClient))
            registry.register(makeWriteObjectiveSnapshotTool(backendClient: backendClient))
        } else {
            registry.register(makeFetchAgentLogsTool(modelContext: context))
        }
        await runScheduler(
            context: sharedModelContext,
            modelContainer: container,
            client: client,
            registry: registry,
            backendClient: backendClient,
            emailIngestor: emailIngestor,
            agentMailBridge: agentMailBridge,
            dropzoneDir: dropzoneDir,
            webhookPort: settings.webhookPort,
            clockIntervalSeconds: settings.schedulerIntervalSeconds,
            settings: settings
        )
    } else {
        if let backendClient {
            registry.register(makeFetchAgentLogsTool(backendClient: backendClient))
            registry.register(makeFetchAgentLogDigestTool(backendClient: backendClient))
        } else {
            registry.register(makeFetchAgentLogsTool(modelContext: context))
        }
        print("[Runner] No-action single-run mode. Exiting.")
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
    agentMailBridge: AgentMailBridge?,
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
    let imapPoller: IMAPEmailPoller?
    let agentMailPoller: AgentMailPoller?
    if let agentMailBridge {
        let poller = AgentMailPoller(bridge: agentMailBridge, interval: settings.agentMailPollSeconds)
        await poller.start()
        agentMailPoller = poller
        imapPoller = nil
    } else if settings.imapEnabled {
        let poller = IMAPEmailPoller(settings: settings, inboxDir: emailIngestor.directory)
        await poller.start()
        imapPoller = poller
        agentMailPoller = nil
    } else {
        imapPoller = nil
        agentMailPoller = nil
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
    var backgroundTasks: [Task<Void, Never>] = []
    if let backendClient {
        backgroundTasks.append(Task(priority: .utility) {
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
        })

        // Agent registration + heartbeat: registers capabilities on startup, then heartbeats
        // every 15s so TaskExecutorJob can route tasks to this agent by capability.
        let agentId = "mac-agent-\(webhookPort)"
        let webhookURLString = settings.agentWebhookPublicURL ?? "http://127.0.0.1:\(webhookPort)"
        var agentCapabilities = [
            "web_search", "file_read", "objective_research",
            "life_context", "work_units",
            "calendar", "reminders", "shell_diagnostics",
            "site_scout"
        ]
        if settings.notificationEmail != nil || settings.imapEnabled || settings.agentMailEnabled {
            agentCapabilities.append("email")
        }
        if settings.githubPAT != nil { agentCapabilities.append("github") }
        if !settings.localFileAllowedDirectories.isEmpty { agentCapabilities.append("local_file_read") }

        backgroundTasks.append(Task(priority: .utility) {
            while !Task.isCancelled {
                do {
                    let email = await agentMailBridge?.getInboxId() ?? settings.imapUsername
                    try await backendClient.registerAgent(
                        agentId: agentId,
                        capabilities: agentCapabilities,
                        webhookURL: webhookURLString,
                        emailAddress: email
                    )
                } catch {
                    print("[Scheduler] agent registration failed: \(error)")
                }
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        })
    }

    print("""
        [Scheduler] Event-driven scheduler started.
          Inbox:    \(emailIngestor.directory.path)
          Inbound:  \(dropzoneDir.path)
          Webhook:  port \(webhookPort) (chat wake: POST JSON {"agentkvt":"process_chat"})
          Clock:    every \(clockIntervalSeconds)s
        """)
    if backendClient != nil {
        print("  Remote:   backend chat queue, chat_wake long-poll, and inbound-file sync enabled")
    }
    let shutdownBackgroundTasks = backgroundTasks

    // ── Run forever — drain loop blocks (async suspends) until the process exits ──
    await withTaskCancellationHandler {
        await executionQueue.run()
    } onCancel: {
        print("[Scheduler] Cancellation received — stopping watchers, timers, and webhook listener.")
        webhookListener.stop()
        inboxWatcher.stop()
        inboundWatcher.stop()
        clockTimer.cancel()
        shutdownBackgroundTasks.forEach { $0.cancel() }
        Task {
            if let imapPoller {
                await imapPoller.stop()
            }
            if let agentMailPoller {
                await agentMailPoller.stop()
            }
            await executionQueue.stop()
        }
    }
}
