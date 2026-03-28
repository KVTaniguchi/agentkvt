import Foundation
import ManagerCore
import SwiftData

/// The strict serial execution engine for AgentKVT.
///
/// ## Why an actor?
/// Swift actors guarantee that at most one method body runs at a time on their
/// executor. Combined with `for await` (which suspends — not blocks — the loop
/// body while awaiting the LLM), we get a single-inflight invariant enforced at
/// the compiler level: while `missionRunner.run()` is suspended awaiting an
/// Ollama response, new triggers are buffered inside `AgentQueue` and processed
/// only after the current task completes.
///
/// ## Trigger priority
/// | Source                     | Priority |
/// |----------------------------|----------|
/// | Webhook (user intent)      | .high    |
/// | Chat wake (`process_chat`) | .high    |
/// | CloudKit (iOS sync)        | .high    |
/// | Email / inbound file       | .normal  |
/// | 60-second clock tick       | .low     |
///
/// When multiple triggers accumulate while the LLM is busy, they are drained in
/// priority order after the current inference finishes.
actor MissionExecutionQueue {

    // MARK: - Dependencies (all actor-isolated; safe from any thread via await)

    private let modelContext: ModelContext
    private let modelContainer: ModelContainer
    private let scheduler: MissionScheduler
    private let missionRunner: MissionRunner
    private let chatRunner: ChatRunner
    private let dropzone: DropzoneService
    private let dropzoneDir: URL
    private let emailIngestor: EmailIngestor
    private let cloudInbound: CloudInboundService
    private let backendClient: BackendAPIClient?

    // MARK: - Trigger buffer (priority-sorted, bounded)

    private let agentQueue: AgentQueue

    // MARK: - Init

    init(
        modelContext: SharedModelContext,
        modelContainer: ModelContainer,
        client: OllamaClient,
        registry: ToolRegistry,
        backendClient: BackendAPIClient?,
        emailIngestor: EmailIngestor,
        dropzoneDir: URL
    ) {
        self.modelContext = modelContext.raw
        self.modelContainer = modelContainer
        self.scheduler = MissionScheduler()
        self.backendClient = backendClient
        let logWriter: any MissionLogWriting = if let backendClient {
            BackendMissionLogWriter(backendClient: backendClient)
        } else {
            SwiftDataMissionLogWriter(modelContext: modelContext.raw)
        }
        self.missionRunner = MissionRunner(
            modelContext: modelContext.raw,
            client: client,
            registry: registry,
            logWriter: logWriter
        )
        self.chatRunner = ChatRunner(modelContext: modelContext.raw, client: client, registry: registry)
        self.dropzoneDir = dropzoneDir
        self.dropzone = DropzoneService(directory: dropzoneDir)
        self.emailIngestor = emailIngestor
        self.cloudInbound = CloudInboundService(modelContext: modelContext.raw, directory: dropzoneDir)
        self.agentQueue = AgentQueue()
    }

    // MARK: - Producer API
    //
    // Called by external producers (DirectoryWatcher callbacks, WebhookListener, clock timer,
    // CloudKitObserver) which are NOT actor-isolated. The `Task { }` here is intentional:
    // it lets the non-isolated callback return immediately while the enqueue happens
    // asynchronously on the actor's executor.

    nonisolated func enqueue(_ item: AgentQueue.WorkItem, priority: AgentQueue.Priority = .normal) {
        Task { await agentQueue.enqueue(item, priority: priority) }
    }

    // MARK: - Main drain loop

    /// Runs forever. Call with `await` from the top-level async entry point to keep
    /// the process alive. The `for await` loop suspends (not blocks) while waiting
    /// for the next signal from `agentQueue.workAvailable`, releasing the actor's
    /// executor so `enqueue()` calls can land in the meantime.
    ///
    /// Serial guarantee: the inner `while let` drains the entire priority buffer before
    /// the outer `for await` can receive the next signal. Each `await dispatch(item)`
    /// suspends here until the LLM call + tool loop completes — so the next item is
    /// never started while an inference is in flight.
    func run() async {
        for await _ in agentQueue.workAvailable {
            while let item = await agentQueue.dequeueNext() {
                do {
                    try await dispatch(item)
                } catch {
                    print("[MissionExecutionQueue] Dispatch error for \(item): \(error)")
                }
            }
        }
    }

    // MARK: - Dispatch

    private func dispatch(_ item: AgentQueue.WorkItem) async throws {
        switch item {

        // ── Clock tick ──────────────────────────────────────────────────────────
        // Low-priority background heartbeat: sync inbound files, TTL-evict ephemeral pins,
        // process pending chat messages, run workunit_board missions when the board has
        // active WorkUnits, then run any CRON-scheduled missions that are now due.
        case .clockTick:
            cloudInbound.syncInboundFiles()
            do {
                try StigmergyBoardMaintenance.evictExpiredEphemeralPins(modelContext: modelContext)
            } catch {
                print("[MissionExecutionQueue] Ephemeral pin eviction failed: \(error)")
            }
            while try await chatRunner.processNextPendingMessage() {}

            if let backendClient {
                let allMissions = try await backendClient.fetchMissions().map { $0.asRequest() }
                let dueScheduledMissions = try await backendClient.fetchDueMissions(at: Date()).map { $0.asRequest() }
                print("[MissionExecutionQueue] Clock tick: \(describeRemoteMissionSnapshot(allMissions, dueScheduledMissions: dueScheduledMissions))")
                try await runRemoteMissions(dueScheduledMissions, using: backendClient, reason: "scheduled mission")
                return
            }

            let staleContextMissionCount = (try? modelContext.fetch(FetchDescriptor<MissionDefinition>()).count) ?? -1
            let fetchContext = freshContext()
            let missions = try fetchContext.fetch(FetchDescriptor<MissionDefinition>())
            if staleContextMissionCount != missions.count {
                print("[MissionExecutionQueue] Fresh-context visibility differs: long-lived context sees \(staleContextMissionCount), fresh context sees \(missions.count).")
            }
            let dueScheduledMissions = scheduler.dueMissions(from: missions)
            let storeCensus = describeStoreCensus(in: fetchContext, missionCount: missions.count)
            print("[MissionExecutionQueue] Clock tick: \(describeMissionSnapshot(missions, dueScheduledMissions: dueScheduledMissions, storeCensus: storeCensus))")
            if try StigmergyBoardMaintenance.hasActiveWorkUnits(modelContext: fetchContext) {
                let boardSchedule = WorkUnit.boardMissionTriggerSchedule
                for mission in missions where mission.isEnabled && mission.triggerSchedule == boardSchedule {
                    mission.lastRunAt = Date()
                    mission.updatedAt = Date()
                    try fetchContext.save()
                    let summaries = existingActionSummaries(for: mission.id, in: fetchContext)
                    do {
                        try await missionRunner.run(MissionRunner.Request(mission).with(existingActionItemSummaries: summaries))
                        print("[MissionExecutionQueue] Ran work unit board mission: \(mission.missionName)")
                    } catch {
                        print("[MissionExecutionQueue] Work unit board mission '\(mission.missionName)' failed: \(error)")
                    }
                }
            }

            for mission in dueScheduledMissions {
                mission.lastRunAt = Date()
                mission.updatedAt = Date()
                try fetchContext.save()
                let summaries = existingActionSummaries(for: mission.id, in: fetchContext)
                do {
                    try await missionRunner.run(MissionRunner.Request(mission).with(existingActionItemSummaries: summaries))
                    print("[MissionExecutionQueue] Ran scheduled mission: \(mission.missionName)")
                } catch {
                    print("[MissionExecutionQueue] Scheduled mission '\(mission.missionName)' failed: \(error)")
                }
            }

        // ── Raw .eml file arrived via FSEvents ──────────────────────────────────
        case .emailFile(let url):
            print("[MissionExecutionQueue] Email arrived: \(url.lastPathComponent)")
            emailIngestor.scan()
            if let backendClient {
                let missions = try await backendClient.fetchMissions().map { $0.asRequest() }
                let matching = missions.filter { $0.isEnabled && $0.allowedToolIds.contains("incoming_email_trigger") }
                try await runRemoteMissions(matching, using: backendClient, reason: "email mission")
                return
            }
            let fetchContext = freshContext()
            let missions = try fetchContext.fetch(FetchDescriptor<MissionDefinition>())
            for mission in missions where mission.isEnabled
                && mission.allowedMCPTools.contains("incoming_email_trigger") {
                mission.lastRunAt = Date()
                mission.updatedAt = Date()
                try fetchContext.save()
                let summaries = existingActionSummaries(for: mission.id, in: fetchContext)
                do {
                    try await missionRunner.run(MissionRunner.Request(mission).with(existingActionItemSummaries: summaries))
                    print("[MissionExecutionQueue] Ran email mission: \(mission.missionName)")
                } catch {
                    print("[MissionExecutionQueue] Email mission '\(mission.missionName)' failed: \(error)")
                }
            }

        // ── Inbound dropzone file arrived via FSEvents ──────────────────────────
        case .inboundFile(let url):
            print("[MissionExecutionQueue] Inbound file arrived: \(url.lastPathComponent)")
            dropzone.scan()
            if let backendClient {
                let missions = try await backendClient.fetchMissions().map { $0.asRequest() }
                let matching = missions.filter { mission in
                    mission.isEnabled &&
                    (mission.allowedToolIds.contains("list_dropzone_files") ||
                        mission.allowedToolIds.contains("read_dropzone_file"))
                }
                try await runRemoteMissions(matching, using: backendClient, reason: "inbound file mission")
                return
            }
            let fetchContext = freshContext()
            let missions = try fetchContext.fetch(FetchDescriptor<MissionDefinition>())
            for mission in missions where mission.isEnabled
                && (mission.allowedMCPTools.contains("list_dropzone_files")
                    || mission.allowedMCPTools.contains("read_dropzone_file")) {
                mission.lastRunAt = Date()
                mission.updatedAt = Date()
                try fetchContext.save()
                let summaries = existingActionSummaries(for: mission.id, in: fetchContext)
                do {
                    try await missionRunner.run(MissionRunner.Request(mission).with(existingActionItemSummaries: summaries))
                    print("[MissionExecutionQueue] Ran inbound file mission: \(mission.missionName)")
                } catch {
                    print("[MissionExecutionQueue] Inbound file mission '\(mission.missionName)' failed: \(error)")
                }
            }

        // ── Webhook POST received ────────────────────────────────────────────────
        // High priority: represents explicit external intent. Written to dropzone
        // so webhook missions can read it via read_dropzone_file.
        case .webhook(let payload):
            print("[MissionExecutionQueue] Webhook received (\(payload.count) bytes)")
            let filename = "webhook_\(Int(Date().timeIntervalSince1970)).json"
            try? payload.write(
                to: dropzoneDir.appendingPathComponent(filename),
                atomically: true,
                encoding: .utf8
            )
            if let backendClient {
                let missions = try await backendClient.fetchMissions().map { $0.asRequest() }
                let matching = missions.filter { $0.isEnabled && $0.triggerSchedule == "webhook" }
                try await runRemoteMissions(matching, using: backendClient, reason: "webhook mission")
                return
            }
            let fetchContext = freshContext()
            let missions = try fetchContext.fetch(FetchDescriptor<MissionDefinition>())
            for mission in missions where mission.isEnabled
                && mission.triggerSchedule == "webhook" {
                mission.lastRunAt = Date()
                mission.updatedAt = Date()
                try fetchContext.save()
                let summaries = existingActionSummaries(for: mission.id, in: fetchContext)
                do {
                    try await missionRunner.run(MissionRunner.Request(mission).with(existingActionItemSummaries: summaries))
                    print("[MissionExecutionQueue] Ran webhook mission: \(mission.missionName)")
                } catch {
                    print("[MissionExecutionQueue] Webhook mission '\(mission.missionName)' failed: \(error)")
                }
            }

        // ── Chat wake webhook (LAN POST `{"agentkvt":"process_chat"}`) ─────────────
        case .processPendingChat:
            print("[MissionExecutionQueue] processPendingChat: draining pending chat.")
            do {
                while try await chatRunner.processNextPendingMessage() {}
            } catch {
                print("[MissionExecutionQueue] processPendingChat failed: \(error)")
            }

        // ── CloudKit sync: iOS→Mac SwiftData changes (chat, email summaries, etc.) ─
        // Remote changes fire for any synced model. Always drain pending chat first so
        // user messages are answered as soon as CloudKit delivers them — not only on
        // the low-priority 60s clock tick (which previously made chat feel stuck when
        // there were no IncomingEmailSummary rows).
        case .cloudKitSync:
            do {
                while try await chatRunner.processNextPendingMessage() {}
            } catch {
                print("[MissionExecutionQueue] CloudKit sync: chat processing failed: \(error)")
            }

            let fetchContext = freshContext()
            let descriptor = FetchDescriptor<IncomingEmailSummary>(
                predicate: #Predicate { !$0.processedByMac }
            )
            let pending = (try? fetchContext.fetch(descriptor)) ?? []
            guard !pending.isEmpty else {
                print("[MissionExecutionQueue] CloudKit sync: no pending email summaries.")
                return
            }
            print("[MissionExecutionQueue] CloudKit sync: \(pending.count) pending email summary(ies).")
            if let backendClient {
                let missions = try await backendClient.fetchMissions().map { $0.asRequest() }
                let matching = missions.filter { $0.isEnabled && $0.allowedToolIds.contains("fetch_email_summaries") }
                try await runRemoteMissions(matching, using: backendClient, reason: "CloudKit summary mission")
                return
            }
            let missions = try fetchContext.fetch(FetchDescriptor<MissionDefinition>())
            for mission in missions where mission.isEnabled
                && mission.allowedMCPTools.contains("fetch_email_summaries") {
                mission.lastRunAt = Date()
                mission.updatedAt = Date()
                try fetchContext.save()
                let summaries = existingActionSummaries(for: mission.id, in: fetchContext)
                do {
                    try await missionRunner.run(MissionRunner.Request(mission).with(existingActionItemSummaries: summaries))
                    print("[MissionExecutionQueue] Ran CloudKit summary mission: \(mission.missionName)")
                } catch {
                    print("[MissionExecutionQueue] CloudKit summary mission '\(mission.missionName)' failed: \(error)")
                }
            }
        }
    }

    private func describeMissionSnapshot(
        _ missions: [MissionDefinition],
        dueScheduledMissions: [MissionDefinition],
        storeCensus: String
    ) -> String {
        guard !missions.isEmpty else {
            return "0 missions visible on Mac store. \(storeCensus)"
        }

        let enabledCount = missions.filter(\.isEnabled).count
        let missionList = missions
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { mission in
                "\(mission.missionName) [\(mission.triggerSchedule)] enabled=\(mission.isEnabled) lastRun=\(mission.lastRunAt.map(Self.logTimestamp) ?? "never")"
            }
            .joined(separator: "; ")

        if dueScheduledMissions.isEmpty {
            return "\(missions.count) mission(s) visible, \(enabledCount) enabled, 0 due. Visible: \(missionList)"
        }

        let dueNames = dueScheduledMissions.map(\.missionName).joined(separator: ", ")
        return "\(missions.count) mission(s) visible, \(enabledCount) enabled, \(dueScheduledMissions.count) due now (\(dueNames)). Visible: \(missionList)"
    }

    private func describeStoreCensus(in context: ModelContext, missionCount: Int) -> String {
        let familyMemberCount = (try? context.fetch(FetchDescriptor<FamilyMember>()).count) ?? -1
        let actionItemCount = (try? context.fetch(FetchDescriptor<ActionItem>()).count) ?? -1
        let agentLogCount = (try? context.fetch(FetchDescriptor<AgentLog>()).count) ?? -1
        let lifeContextCount = (try? context.fetch(FetchDescriptor<LifeContext>()).count) ?? -1
        let inboundFileCount = (try? context.fetch(FetchDescriptor<InboundFile>()).count) ?? -1
        let incomingEmailSummaryCount = (try? context.fetch(FetchDescriptor<IncomingEmailSummary>()).count) ?? -1
        return "Store census: familyMembers=\(familyMemberCount), missions=\(missionCount), actionItems=\(actionItemCount), agentLogs=\(agentLogCount), lifeContexts=\(lifeContextCount), inboundFiles=\(inboundFileCount), emailSummaries=\(incomingEmailSummaryCount)."
    }

    private func freshContext() -> ModelContext {
        ModelContext(modelContainer)
    }

    private func runRemoteMissions(
        _ missions: [MissionRunner.Request],
        using backendClient: BackendAPIClient,
        reason: String
    ) async throws {
        for mission in missions {
            let runTimestamp = Date()
            _ = try await backendClient.markMissionRun(missionId: mission.id, at: runTimestamp)

            let existingSummaries: [String]
            do {
                let existing = try await backendClient.fetchUnhandledActionItems(missionId: mission.id)
                existingSummaries = existing.map { item in
                    "\"\(item.title)\" [\(item.systemIntent)] — created \(Self.relativeAge(of: item.timestamp))"
                }
            } catch {
                existingSummaries = []
                print("[MissionExecutionQueue] Could not fetch existing actions for '\(mission.missionName)': \(error)")
            }

            do {
                try await missionRunner.run(mission.with(existingActionItemSummaries: existingSummaries))
                print("[MissionExecutionQueue] Ran \(reason): \(mission.missionName)")
            } catch {
                print("[MissionExecutionQueue] \(reason.capitalized) '\(mission.missionName)' failed: \(error)")
            }
        }
    }

    private func existingActionSummaries(for missionId: UUID, in context: ModelContext) -> [String] {
        let descriptor = FetchDescriptor<ActionItem>(
            predicate: #Predicate<ActionItem> { !$0.isHandled }
        )
        guard let items = try? context.fetch(descriptor) else { return [] }
        let missionItems = items.filter { $0.missionId == missionId }
        guard !missionItems.isEmpty else { return [] }
        return missionItems.map { item in
            "\"\(item.title)\" [\(item.systemIntent)] — created \(Self.relativeAge(of: item.timestamp))"
        }
    }

    private static func relativeAge(of date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        if seconds < 86400 { return "\(seconds / 3600) hr ago" }
        return "\(seconds / 86400) day(s) ago"
    }

    private func describeRemoteMissionSnapshot(
        _ missions: [MissionRunner.Request],
        dueScheduledMissions: [MissionRunner.Request]
    ) -> String {
        guard !missions.isEmpty else {
            return "0 missions visible from backend. Store census: backend-only mission source."
        }

        let enabledCount = missions.filter(\.isEnabled).count
        let missionList = missions
            .sorted { lhs, rhs in
                (lhs.lastRunAt ?? .distantPast) > (rhs.lastRunAt ?? .distantPast)
            }
            .map { mission in
                "\(mission.missionName) [\(mission.triggerSchedule)] enabled=\(mission.isEnabled) lastRun=\(mission.lastRunAt.map(Self.logTimestamp) ?? "never")"
            }
            .joined(separator: "; ")

        if dueScheduledMissions.isEmpty {
            return "\(missions.count) backend mission(s) visible, \(enabledCount) enabled, 0 due. Visible: \(missionList)"
        }

        let dueNames = dueScheduledMissions.map(\.missionName).joined(separator: ", ")
        return "\(missions.count) backend mission(s) visible, \(enabledCount) enabled, \(dueScheduledMissions.count) due now (\(dueNames)). Visible: \(missionList)"
    }

    private static func logTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
