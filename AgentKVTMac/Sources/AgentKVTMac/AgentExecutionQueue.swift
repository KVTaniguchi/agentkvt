import Foundation
import ManagerCore
import SwiftData

/// The event router for AgentKVT.
///
/// ## Why an actor?
/// Swift actors guarantee that at most one method body runs at a time on their
/// executor. We use that to keep chat, scheduled missions, and generic webhook
/// dispatch serialized and responsive. Objective execution is intentionally
/// handed off to a separate bounded worker pool so chat does not stall behind
/// long-running research.
actor AgentExecutionQueue {

    // MARK: - Dependencies (all actor-isolated; safe from any thread via await)

    private let modelContext: ModelContext
    private let modelContainer: ModelContainer
    private let chatRunner: ChatRunner
    private let dropzone: DropzoneService
    private let dropzoneDir: URL
    private let emailIngestor: EmailIngestor
    private let cloudInbound: CloudInboundService
    private let backendInbound: BackendInboundService?
    private let backendClient: BackendAPIClient?
    private let objectiveExecutionPool: ObjectiveExecutionPool

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
        dropzoneDir: URL,
        objectiveWorkerConcurrency: Int
    ) {
        self.modelContext = modelContext.raw
        self.modelContainer = modelContainer
        self.backendClient = backendClient
        if let backendClient {
            self.chatRunner = ChatRunner(backendClient: backendClient, client: client, registry: registry)
            self.backendInbound = BackendInboundService(backendClient: backendClient, directory: dropzoneDir)
        } else {
            self.chatRunner = ChatRunner(modelContext: modelContext.raw, client: client, registry: registry)
            self.backendInbound = nil
        }
        self.dropzoneDir = dropzoneDir
        self.dropzone = DropzoneService(directory: dropzoneDir)
        self.emailIngestor = emailIngestor
        self.cloudInbound = CloudInboundService(modelContext: modelContext.raw, directory: dropzoneDir)
        self.agentQueue = AgentQueue()
        
        let objectiveLogWriter: any AgentTaskLogWriting = if let backendClient {
            BackendAgentTaskLogWriter(backendClient: backendClient)
        } else {
            SwiftDataAgentTaskLogWriter(modelContext: modelContext.raw)
        }
        let objectiveTaskRunner = AgentTaskRunner(
            modelContext: modelContext.raw,
            client: client,
            registry: registry,
            logWriter: objectiveLogWriter
        )
        self.objectiveExecutionPool = ObjectiveExecutionPool(
            modelContainer: modelContainer,
            client: client,
            taskRunner: objectiveTaskRunner,
            backendClient: backendClient,
            maxConcurrentWorkers: objectiveWorkerConcurrency
        )
    }

    // MARK: - Producer API

    nonisolated func enqueue(_ item: AgentQueue.WorkItem, priority: AgentQueue.Priority = .normal) {
        Task { await agentQueue.enqueue(item, priority: priority) }
    }

    // MARK: - Main drain loop

    func run() async {
        await objectiveExecutionPool.start()
        for await _ in agentQueue.workAvailable {
            while let item = await agentQueue.dequeueNext() {
                do {
                    try await dispatch(item)
                } catch {
                    print("[AgentExecutionQueue] Dispatch error for \\(item): \\(error)")
                }
            }
        }
    }

    func stop() async {
        await objectiveExecutionPool.stop()
        await agentQueue.finish()
    }

    // MARK: - Dispatch

    private func dispatch(_ item: AgentQueue.WorkItem) async throws {
        switch item {

        // ── Clock tick ──────────────────────────────────────────────────────────
        case .clockTick:
            if let backendInbound {
                await backendInbound.syncInboundFiles()
            } else {
                cloudInbound.syncInboundFiles()
            }
            do {
                try StigmergyBoardMaintenance.evictExpiredEphemeralPins(modelContext: modelContext)
            } catch {
                print("[AgentExecutionQueue] Ephemeral pin eviction failed: \\(error)")
            }
            while try await chatRunner.processNextPendingMessage() {}

        // ── Raw .eml file arrived via FSEvents ──────────────────────────────────
        case .emailFile(_):
            emailIngestor.scan()

        // ── Inbound dropzone file arrived via FSEvents ──────────────────────────
        case .inboundFile(_):
            dropzone.scan()

        // ── Webhook POST received ────────────────────────────────────────────────
        case .webhook(let payload):
            let filename = "webhook_\\(Int(Date().timeIntervalSince1970)).json"
            try? payload.write(
                to: dropzoneDir.appendingPathComponent(filename),
                atomically: true,
                encoding: .utf8
            )

            // Dedicated handler for Rails TaskExecutorJob dispatches.
            if let taskPayload = TaskSearchPayload(json: payload) {
                await objectiveExecutionPool.enqueue(taskPayload)
                return
            }

        // ── Chat wake webhook (LAN POST `{"agentkvt":"process_chat"}`) ─────────────
        case .processPendingChat:
            do {
                while try await chatRunner.processNextPendingMessage() {}
            } catch {
                print("[AgentExecutionQueue] processPendingChat failed: \(error)")
            }

        // ── CloudKit sync: iOS→Mac SwiftData changes (chat, email summaries, etc.) ─
        case .cloudKitSync:
            guard backendClient == nil else {
                return
            }
            do {
                while try await chatRunner.processNextPendingMessage() {}
            } catch {
                print("[AgentExecutionQueue] cloudKitSync chat drain failed: \(error)")
            }
        }
    }

    private func freshContext() -> ModelContext {
        ModelContext(modelContainer)
    }

}

// MARK: - TaskSearchPayload

/// Decoded form of the JSON body that Rails TaskExecutorJob POSTs to the Mac webhook.
struct TaskSearchPayload: Sendable {
    let taskId: String
    let objectiveId: String
    let description: String
    let taskKind: String?
    let allowedToolIds: [String]
    let requiredCapabilities: [String]
    let doneWhen: String?
    /// Full parent objective goal from Rails (`objective.goal`); optional for older webhook clients.
    let objectiveGoal: String?

    /// Returns nil if the body is not a valid run_task_search payload.
    init?(json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[TaskSearchPayload] Failed to parse JSON body string")
            return nil
        }
        guard obj["agentkvt"] as? String == "run_task_search" else {
            return nil // Not our webhook type, ignore silently.
        }
        guard let taskId = obj["task_id"] as? String,
              let objectiveId = obj["objective_id"] as? String,
              let description = obj["description"] as? String,
              !taskId.isEmpty, !objectiveId.isEmpty, !description.isEmpty
        else { 
            print("[TaskSearchPayload] Invalid payload keys!")
            return nil 
        }

        self.taskId = taskId
        self.objectiveId = objectiveId
        self.description = description
        self.taskKind = Self.normalizedString(obj["task_kind"])
        self.allowedToolIds = Self.stringArray(obj["allowed_tool_ids"])
        self.requiredCapabilities = Self.stringArray(obj["required_capabilities"])
        self.doneWhen = Self.normalizedString(obj["done_when"])
        if let g = obj["objective_goal"] as? String {
            let t = g.trimmingCharacters(in: .whitespacesAndNewlines)
            self.objectiveGoal = t.isEmpty ? nil : t
        } else {
            self.objectiveGoal = nil
        }
    }

    private static func normalizedString(_ raw: Any?) -> String? {
        guard let value = raw as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stringArray(_ raw: Any?) -> [String] {
        let values: [Any]
        switch raw {
        case let array as [Any]:
            values = array
        case let string as String:
            values = [string]
        default:
            values = []
        }

        return values
            .map { String(describing: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
