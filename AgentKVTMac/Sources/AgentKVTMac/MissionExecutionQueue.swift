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
/// | Email / inbound file / CloudKit | .normal |
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

    // MARK: - Trigger buffer (priority-sorted, bounded)

    private let agentQueue: AgentQueue

    // MARK: - Init

    init(
        modelContext: SharedModelContext,
        modelContainer: ModelContainer,
        client: OllamaClient,
        registry: ToolRegistry,
        emailIngestor: EmailIngestor,
        dropzoneDir: URL
    ) {
        self.modelContext = modelContext.raw
        self.modelContainer = modelContainer
        self.scheduler = MissionScheduler()
        self.missionRunner = MissionRunner(modelContext: modelContext.raw, client: client, registry: registry)
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

            let staleContextMissionCount = (try? modelContext.fetch(FetchDescriptor<MissionDefinition>()).count) ?? -1
            let fetchContext = freshContext()
            let missions = try fetchContext.fetch(FetchDescriptor<MissionDefinition>())
            if staleContextMissionCount != missions.count {
                print("[MissionExecutionQueue] Fresh-context visibility differs: long-lived context sees \(staleContextMissionCount), fresh context sees \(missions.count).")
            }
            let dueScheduledMissions = scheduler.dueMissions(from: missions)
            print("[MissionExecutionQueue] Clock tick: \(describeMissionSnapshot(missions, dueScheduledMissions: dueScheduledMissions))")
            if try StigmergyBoardMaintenance.hasActiveWorkUnits(modelContext: fetchContext) {
                let boardSchedule = WorkUnit.boardMissionTriggerSchedule
                for mission in missions where mission.isEnabled && mission.triggerSchedule == boardSchedule {
                mission.lastRunAt = Date()
                mission.updatedAt = Date()
                try fetchContext.save()
                let request = MissionRunner.Request(mission)
                do {
                    try await missionRunner.run(request)
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
                let request = MissionRunner.Request(mission)
                do {
                    try await missionRunner.run(request)
                    print("[MissionExecutionQueue] Ran scheduled mission: \(mission.missionName)")
                } catch {
                    print("[MissionExecutionQueue] Scheduled mission '\(mission.missionName)' failed: \(error)")
                }
            }

        // ── Raw .eml file arrived via FSEvents ──────────────────────────────────
        case .emailFile(let url):
            print("[MissionExecutionQueue] Email arrived: \(url.lastPathComponent)")
            emailIngestor.scan()
            let fetchContext = freshContext()
            let missions = try fetchContext.fetch(FetchDescriptor<MissionDefinition>())
            for mission in missions where mission.isEnabled
                && mission.allowedMCPTools.contains("incoming_email_trigger") {
                mission.lastRunAt = Date()
                mission.updatedAt = Date()
                try fetchContext.save()
                let request = MissionRunner.Request(mission)
                do {
                    try await missionRunner.run(request)
                    print("[MissionExecutionQueue] Ran email mission: \(mission.missionName)")
                } catch {
                    print("[MissionExecutionQueue] Email mission '\(mission.missionName)' failed: \(error)")
                }
            }

        // ── Inbound dropzone file arrived via FSEvents ──────────────────────────
        case .inboundFile(let url):
            print("[MissionExecutionQueue] Inbound file arrived: \(url.lastPathComponent)")
            dropzone.scan()
            let fetchContext = freshContext()
            let missions = try fetchContext.fetch(FetchDescriptor<MissionDefinition>())
            for mission in missions where mission.isEnabled
                && (mission.allowedMCPTools.contains("list_dropzone_files")
                    || mission.allowedMCPTools.contains("read_dropzone_file")) {
                mission.lastRunAt = Date()
                mission.updatedAt = Date()
                try fetchContext.save()
                let request = MissionRunner.Request(mission)
                do {
                    try await missionRunner.run(request)
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
            let fetchContext = freshContext()
            let missions = try fetchContext.fetch(FetchDescriptor<MissionDefinition>())
            for mission in missions where mission.isEnabled
                && mission.triggerSchedule == "webhook" {
                mission.lastRunAt = Date()
                mission.updatedAt = Date()
                try fetchContext.save()
                let request = MissionRunner.Request(mission)
                do {
                    try await missionRunner.run(request)
                    print("[MissionExecutionQueue] Ran webhook mission: \(mission.missionName)")
                } catch {
                    print("[MissionExecutionQueue] Webhook mission '\(mission.missionName)' failed: \(error)")
                }
            }

        // ── CloudKit sync: IncomingEmailSummary records from iOS ─────────────────
        // The iOS EdgeSummarizationService ran Apple Intelligence on an email and
        // pushed a compact IncomingEmailSummary via CloudKit. Find missions that
        // declare fetch_email_summaries in their allowed tools and run them.
        case .cloudKitSync:
            let fetchContext = freshContext()
            let descriptor = FetchDescriptor<IncomingEmailSummary>(
                predicate: #Predicate { !$0.processedByMac }
            )
            let pending = (try? fetchContext.fetch(descriptor)) ?? []
            guard !pending.isEmpty else {
                print("[MissionExecutionQueue] CloudKit sync: no pending summaries.")
                return
            }
            print("[MissionExecutionQueue] CloudKit sync: \(pending.count) pending summary(ies).")
            let missions = try fetchContext.fetch(FetchDescriptor<MissionDefinition>())
            for mission in missions where mission.isEnabled
                && mission.allowedMCPTools.contains("fetch_email_summaries") {
                mission.lastRunAt = Date()
                mission.updatedAt = Date()
                try fetchContext.save()
                let request = MissionRunner.Request(mission)
                do {
                    try await missionRunner.run(request)
                    print("[MissionExecutionQueue] Ran CloudKit summary mission: \(mission.missionName)")
                } catch {
                    print("[MissionExecutionQueue] CloudKit summary mission '\(mission.missionName)' failed: \(error)")
                }
            }
        }
    }

    private func describeMissionSnapshot(
        _ missions: [MissionDefinition],
        dueScheduledMissions: [MissionDefinition]
    ) -> String {
        guard !missions.isEmpty else {
            return "0 missions visible on Mac store."
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

    private func freshContext() -> ModelContext {
        ModelContext(modelContainer)
    }

    private static func logTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
