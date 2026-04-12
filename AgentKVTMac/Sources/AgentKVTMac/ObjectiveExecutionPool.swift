import Foundation
import ManagerCore
import SwiftData

private struct ObjectiveWorkerSlot: Sendable {
    let id: UUID
    let label: String
}

/// A (objectiveId, taskId) group that has research work units but no synthesis unit.
/// Created at startup to resume objectives whose supervisor task was lost on app restart.
private struct OrphanedObjectiveGroup: Sendable {
    let objectiveId: UUID
    let taskId: UUID
    let rootTaskDescription: String
    let parentObjectiveGoal: String?
}

actor ObjectiveExecutionPool {
    private let processor: ObjectiveExecutionProcessor
    private let maxConcurrentWorkers: Int

    private var started = false
    private var workerTasks: [Task<Void, Never>] = []
    private var supervisorTaskIds: Set<String> = []

    init(
        modelContainer: ModelContainer,
        client: any OllamaClientProtocol,
        taskRunner: AgentTaskRunner,
        backendClient: BackendAPIClient?,
        maxConcurrentWorkers: Int,
        researchSettleTimeoutSeconds: TimeInterval = 600
    ) {
        self.processor = ObjectiveExecutionProcessor(
            modelContainer: modelContainer,
            client: client,
            taskRunner: taskRunner,
            backendClient: backendClient,
            researchSettleTimeoutSeconds: researchSettleTimeoutSeconds
        )
        self.maxConcurrentWorkers = max(1, maxConcurrentWorkers)
    }

    func start() {
        guard !started else { return }
        started = true
        print("[ObjectiveExecutionPool] starting \(maxConcurrentWorkers) workers")
        for index in 0..<maxConcurrentWorkers {
            let slot = ObjectiveWorkerSlot(id: UUID(), label: "objective-worker-\(index + 1)")
            let task = Task.detached(priority: .utility) { [processor] in
                await processor.runWorkerLoop(slot: slot)
            }
            workerTasks.append(task)
        }
        // Sweep for objectives whose supervisor was lost when the app last restarted.
        Task.detached(priority: .utility) { [self] in
            await self.sweepOrphanedObjectives()
        }
    }

    /// Finds objective/task groups that have research work units but no synthesis unit,
    /// then spawns a recovery supervisor for each one. Called once at startup.
    private func sweepOrphanedObjectives() async {
        let orphans = processor.findOrphanedObjectiveGroups()
        guard !orphans.isEmpty else { return }
        print("[ObjectiveExecutionPool] Startup sweep: found \(orphans.count) orphaned objective(s) — resuming synthesis")
        for orphan in orphans {
            guard supervisorTaskIds.insert(orphan.taskId.uuidString).inserted else {
                print("[ObjectiveExecutionPool] recovery: task \(orphan.taskId) already supervised, skipping")
                continue
            }
            Task.detached(priority: .utility) { [processor, taskId = orphan.taskId.uuidString] in
                await processor.resumeFromSynthesis(orphan: orphan)
                await self.finishSupervision(taskId: taskId)
            }
        }
    }

    func enqueue(_ payload: TaskSearchPayload) {
        start()
        print("[ObjectiveExecutionPool] enqueueing task \(payload.taskId)")
        guard supervisorTaskIds.insert(payload.taskId).inserted else { 
            print("[ObjectiveExecutionPool] ignoring task \(payload.taskId) because it is already supervised")
            return 
        }

        Task.detached(priority: .utility) { [processor, taskId = payload.taskId] in
            await processor.superviseObjective(payload: payload)
            await self.finishSupervision(taskId: taskId)
        }
    }

    private func finishSupervision(taskId: String) {
        supervisorTaskIds.remove(taskId)
    }
}

private final class ObjectiveExecutionProcessor: @unchecked Sendable {
    private enum Constants {
        static let objectiveCategory = "objective"
        static let rootType = "objective_root"
        static let researchType = "objective_research"
        static let synthesisType = "objective_synthesis"
    }

    private struct WorkPlan: Codable, Sendable {
        let workUnits: [String]
    }

    private struct ObjectiveWorkPayload: Codable, Sendable {
        let objectiveId: UUID
        let taskId: UUID
        let rootTaskDescription: String
        /// Parent objective goal from Rails webhook (`objective_goal`); nil in older SwiftData payloads.
        let parentObjectiveGoal: String?
        let workDescription: String
        let planningRound: Int
        let workType: String
        var resultSummary: String?
        var lastError: String?
        /// Number of times this work unit has been reset to pending after a transient timeout.
        var retryCount: Int?
    }

    private struct ClaimedWork: Sendable {
        let workUnitId: UUID
        let objectiveId: UUID
        let taskId: UUID
        let title: String
        let workType: String
        let activePhaseHint: String?
        let payload: ObjectiveWorkPayload
    }

    private let modelContainer: ModelContainer
    private let client: any OllamaClientProtocol
    private let taskRunner: AgentTaskRunner
    private let backendClient: BackendAPIClient?
    private let researchSettleTimeoutSeconds: TimeInterval
    /// Serializes SwiftData claim read/modify/save so parallel workers cannot claim the same pending unit.
    private let claimLock = NSLock()

    init(
        modelContainer: ModelContainer,
        client: any OllamaClientProtocol,
        taskRunner: AgentTaskRunner,
        backendClient: BackendAPIClient?,
        researchSettleTimeoutSeconds: TimeInterval
    ) {
        self.modelContainer = modelContainer
        self.client = client
        self.taskRunner = taskRunner
        self.backendClient = backendClient
        self.researchSettleTimeoutSeconds = max(0.1, researchSettleTimeoutSeconds)
    }

    func superviseObjective(payload: TaskSearchPayload) async {
        guard let objectiveId = UUID(uuidString: payload.objectiveId),
              let taskId = UUID(uuidString: payload.taskId) else {
            print("[ObjectiveExecutionPool.Supervisor] ERROR: invalid UUID string in payload: obj=\(payload.objectiveId) task=\(payload.taskId)")
            return
        }

        do {
            let parentGoal = payload.objectiveGoal
            let root = try ensureRootWorkUnit(
                objectiveId: objectiveId,
                taskId: taskId,
                title: payload.description,
                parentObjectiveGoal: parentGoal
            )

            // If research already timed out in a prior supervisor run, skip straight to synthesis
            // with whatever snapshots were gathered rather than re-queueing research work units.
            let alreadyTimedOut = root.activePhaseHint == "timed_out"

            if alreadyTimedOut {
                await logEvent(
                    phase: "objective_supervisor",
                    content: "Supervisor resuming after research timeout — skipping to synthesis for task: \(payload.description)",
                    objectiveId: objectiveId,
                    taskId: taskId,
                    taskName: "Objective Supervisor"
                )
            } else {
                try updateRootState(rootId: root.id, state: WorkUnitState.inProgress.rawValue, phase: "decomposing")
                await logEvent(
                    phase: "objective_supervisor",
                    content: "Supervisor started board work for task: \(payload.description)",
                    objectiveId: objectiveId,
                    taskId: taskId,
                    taskName: "Objective Supervisor"
                )

                let initialUnits = await createResearchRound(
                    objectiveId: objectiveId,
                    taskId: taskId,
                    rootTaskDescription: payload.description,
                    parentObjectiveGoal: parentGoal,
                    planningRound: 1,
                    completedSummaries: []
                )
                if initialUnits == 0 {
                    _ = try createWorkUnit(
                        objectiveId: objectiveId,
                        taskId: taskId,
                        title: payload.description,
                        workType: Constants.researchType,
                        activePhaseHint: "research",
                        planningRound: 1,
                        rootTaskDescription: payload.description,
                        parentObjectiveGoal: parentGoal,
                        priority: 1.0
                    )
                }
                try await waitForResearchToSettle(objectiveId: objectiveId, taskId: taskId)

                let roundOneSummaries = try completedSummaries(objectiveId: objectiveId, taskId: taskId)
                let followUpUnits = await createResearchRound(
                    objectiveId: objectiveId,
                    taskId: taskId,
                    rootTaskDescription: payload.description,
                    parentObjectiveGoal: parentGoal,
                    planningRound: 2,
                    completedSummaries: roundOneSummaries
                )
                if followUpUnits > 0 {
                    try updateRootState(rootId: root.id, state: WorkUnitState.inProgress.rawValue, phase: "follow_up")
                    try await waitForResearchToSettle(objectiveId: objectiveId, taskId: taskId)
                }
            }

            _ = try ensureSynthesisWorkUnit(
                objectiveId: objectiveId,
                taskId: taskId,
                rootTaskDescription: payload.description,
                parentObjectiveGoal: parentGoal
            )
            try updateRootState(rootId: root.id, state: WorkUnitState.inProgress.rawValue, phase: "synthesizing")
            try await waitForSynthesisToSettle(objectiveId: objectiveId, taskId: taskId)
            try updateRootState(rootId: root.id, state: WorkUnitState.done.rawValue, phase: "complete")

            await logEvent(
                phase: "objective_supervisor",
                content: "Objective board completed for task: \(payload.description)",
                objectiveId: objectiveId,
                taskId: taskId,
                taskName: "Objective Supervisor"
            )
        } catch {
            await logEvent(
                phase: "error",
                content: "Objective supervisor failed: \(error)",
                objectiveId: objectiveId,
                taskId: taskId,
                taskName: "Objective Supervisor"
            )
        }
    }

    func runWorkerLoop(slot: ObjectiveWorkerSlot) async {
        print("[ObjectiveWorker] \(slot.label) started finding work")
        while !Task.isCancelled {
            do {
                if let claimed = try claimNextWorkUnit(slot: slot) {
                    try await execute(claimed: claimed, slot: slot)
                } else {
                    try? await Task.sleep(for: .seconds(2))
                }
            } catch {
                await logEvent(
                    phase: "error",
                    content: "Worker loop failed: \(error)",
                    objectiveId: nil,
                    taskId: nil,
                    workUnitId: nil,
                    workerLabel: slot.label,
                    taskName: "Objective Worker \(slot.label)"
                )
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func execute(claimed: ClaimedWork, slot: ObjectiveWorkerSlot) async throws {
        await logEvent(
            phase: "worker_claim",
            content: "Claimed \(claimed.workType) work unit: \(claimed.title)",
            objectiveId: claimed.objectiveId,
            taskId: claimed.taskId,
            workUnitId: claimed.workUnitId,
            workerLabel: slot.label,
            taskName: "Objective Worker \(slot.label)"
        )

        // Idempotency guard for synthesis: if the backend already has a task_summary snapshot
        // for this task, a prior run completed successfully (assistant_final was already posted).
        // Re-running the LLM would post a duplicate assistant_final that the backend rejects with 422.
        // This covers the crash window between the backend log write and the local SwiftData update.
        if claimed.workType == Constants.synthesisType, let backendClient {
            let summaryKey = finalSummaryKey(taskId: claimed.taskId)
            if let snaps = try? await backendClient.fetchResearchSnapshots(
                objectiveId: claimed.objectiveId,
                taskId: claimed.taskId
            ), let existing = snaps.first(where: {
                $0.key == summaryKey && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                await logEvent(
                    phase: "objective_supervisor",
                    content: "Synthesis already completed on server (found \(summaryKey)) — skipping LLM re-run to avoid duplicate log.",
                    objectiveId: claimed.objectiveId,
                    taskId: claimed.taskId,
                    workUnitId: claimed.workUnitId,
                    workerLabel: slot.label,
                    taskName: "Objective Worker \(slot.label)"
                )
                try completeWorkUnit(claimed.workUnitId, summary: existing.value)
                await logEvent(
                    phase: "worker_complete",
                    content: "Completed \(claimed.workType) work unit (idempotent resume): \(claimed.title)",
                    objectiveId: claimed.objectiveId,
                    taskId: claimed.taskId,
                    workUnitId: claimed.workUnitId,
                    workerLabel: slot.label,
                    taskName: "Objective Worker \(slot.label)"
                )
                return
            }
        }

        let heartbeatTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self else { return }
                try? self.touchWorkUnit(
                    workUnitId: claimed.workUnitId,
                    workerId: slot.id,
                    workerLabel: slot.label,
                    phase: claimed.activePhaseHint ?? "working"
                )
            }
        }

        do {
            let serverSnapshotsContext = await fetchServerSnapshotsContext(
                objectiveId: claimed.objectiveId,
                taskId: claimed.taskId
            )
            let resolvedParentGoal = await resolveParentObjectiveGoal(
                payload: claimed.payload,
                objectiveId: claimed.objectiveId
            )
            let request = buildMissionRequest(
                for: claimed,
                workerLabel: slot.label,
                serverSnapshotsContext: serverSnapshotsContext,
                resolvedParentGoal: resolvedParentGoal
            )
            // Count snapshots before the mission so we can detect whether write_objective_snapshot was called.
            let preRunSnapshotCount: Int
            if claimed.workType == Constants.researchType, let backendClient {
                let snaps = try? await backendClient.fetchResearchSnapshots(
                    objectiveId: claimed.objectiveId,
                    taskId: claimed.taskId
                )
                preRunSnapshotCount = snaps?.count ?? 0
            } else {
                preRunSnapshotCount = 0
            }
            let result = try await taskRunner.run(request)
            heartbeatTask.cancel()

            // Block research work units whose final text is raw tool-call JSON (model used text
            // output instead of the tool API). Blocked units are skipped by waitForResearchToSettle
            // so synthesis can still proceed with whatever real research completed.
            if claimed.workType == Constants.researchType && MetaRefusalText.looksLikeRawToolCallOutput(result) {
                try blockWorkUnit(
                    claimed.workUnitId,
                    error: "Research output was raw tool-call JSON syntax instead of prose findings."
                )
                await logEvent(
                    phase: "error",
                    content: "Research work unit blocked: model wrote tool-call JSON as text instead of using tool API.",
                    objectiveId: claimed.objectiveId,
                    taskId: claimed.taskId,
                    workUnitId: claimed.workUnitId,
                    workerLabel: slot.label,
                    taskName: "Objective Worker \(slot.label)"
                )
                return
            }

            // Research fallback: if the model produced valid prose but never called write_objective_snapshot,
            // force-write the result so synthesis always has real data in Postgres.
            if claimed.workType == Constants.researchType,
               let backendClient,
               !MetaRefusalText.isInvalidResearchOutput(result)
            {
                let postRunSnaps = try? await backendClient.fetchResearchSnapshots(
                    objectiveId: claimed.objectiveId,
                    taskId: claimed.taskId
                )
                let postRunCount = postRunSnaps?.count ?? 0
                if postRunCount <= preRunSnapshotCount {
                    let shortId = claimed.workUnitId.uuidString.prefix(8).lowercased()
                    let key = "research_\(shortId)"
                    _ = try? await backendClient.writeResearchSnapshot(
                        objectiveId: claimed.objectiveId,
                        taskId: claimed.taskId,
                        key: key,
                        value: String(result.prefix(4000)),
                        markTaskCompleted: false
                    )
                    await logEvent(
                        phase: "objective_supervisor",
                        content: "Research fallback: force-wrote prose findings to Postgres (model did not call write_objective_snapshot).",
                        objectiveId: claimed.objectiveId,
                        taskId: claimed.taskId,
                        workUnitId: claimed.workUnitId,
                        workerLabel: slot.label,
                        taskName: "Objective Worker \(slot.label)"
                    )
                }
            }

            if claimed.workType == Constants.synthesisType, let backendClient {
                if ObjectiveResearchSnapshotPayload.clientRejectionMessageIfInvalid(result) != nil {
                    try blockWorkUnit(
                        claimed.workUnitId,
                        error: "Model returned JSON instead of a final prose summary; refusing to mark complete."
                    )
                    await logEvent(
                        phase: "error",
                        content: "Synthesis produced JSON as final text; work unit blocked.",
                        objectiveId: claimed.objectiveId,
                        taskId: claimed.taskId,
                        workUnitId: claimed.workUnitId,
                        workerLabel: slot.label,
                        taskName: "Objective Worker \(slot.label)"
                    )
                    return
                }
                let summaryKey = finalSummaryKey(taskId: claimed.taskId)
                let existingSnaps = try? await backendClient.fetchResearchSnapshots(
                    objectiveId: claimed.objectiveId,
                    taskId: claimed.taskId
                )
                let toolRow = existingSnaps?.first { $0.key == summaryKey }
                let toolWroteSummary = toolRow.map { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false

                if toolWroteSummary, let toolRow {
                    // Tool already wrote task_summary_*. Re-upsert the same value with markTaskCompleted: true
                    // so the task is guaranteed to be marked complete regardless of what mark_task_completed
                    // value the model passed to the tool. This is idempotent: Rails only sets delta_note when
                    // the value changes, so re-sending the same prose produces no spurious alert.
                    _ = try? await backendClient.writeResearchSnapshot(
                        objectiveId: claimed.objectiveId,
                        taskId: claimed.taskId,
                        key: summaryKey,
                        value: String(toolRow.value.prefix(8000)),
                        markTaskCompleted: true
                    )
                } else if !toolWroteSummary {
                    if looksLikeMetaRefusal(result) {
                        try blockWorkUnit(
                            claimed.workUnitId,
                            error: "Synthesis final text looked like a meta-refusal instead of research guidance."
                        )
                        await logEvent(
                            phase: "error",
                            content: "Synthesis produced a meta-refusal and did not write task_summary via tools.",
                            objectiveId: claimed.objectiveId,
                            taskId: claimed.taskId,
                            workUnitId: claimed.workUnitId,
                            workerLabel: slot.label,
                            taskName: "Objective Worker \(slot.label)"
                        )
                        return
                    }
                    do {
                        _ = try await backendClient.writeResearchSnapshot(
                            objectiveId: claimed.objectiveId,
                            taskId: claimed.taskId,
                            key: summaryKey,
                            value: String(result.prefix(8000)),
                            markTaskCompleted: true
                        )
                    } catch {
                        try blockWorkUnit(claimed.workUnitId, error: String(describing: error))
                        await logEvent(
                            phase: "error",
                            content: "Synthesis snapshot write failed: \(error)",
                            objectiveId: claimed.objectiveId,
                            taskId: claimed.taskId,
                            workUnitId: claimed.workUnitId,
                            workerLabel: slot.label,
                            taskName: "Objective Worker \(slot.label)"
                        )
                        throw error
                    }
                }
            }

            try completeWorkUnit(claimed.workUnitId, summary: result)

            await logEvent(
                phase: "worker_complete",
                content: "Completed \(claimed.workType) work unit: \(claimed.title)",
                objectiveId: claimed.objectiveId,
                taskId: claimed.taskId,
                workUnitId: claimed.workUnitId,
                workerLabel: slot.label,
                taskName: "Objective Worker \(slot.label)"
            )
        } catch {
            heartbeatTask.cancel()
            let isTransientTimeout = (error as? URLError)?.code == .timedOut
            if isTransientTimeout {
                let currentRetries = claimed.payload.retryCount ?? 0
                if currentRetries < 2 {
                    try resetWorkUnitToPending(claimed.workUnitId, reason: "Ollama request timed out; will retry (attempt \(currentRetries + 1))")
                } else {
                    try blockWorkUnit(claimed.workUnitId, error: "Ollama timed out after \(currentRetries + 1) attempts; blocked to allow synthesis to proceed with available data.")
                }
            } else {
                try blockWorkUnit(claimed.workUnitId, error: String(describing: error))
            }
            await logEvent(
                phase: "error",
                content: "Work unit failed: \(error)",
                objectiveId: claimed.objectiveId,
                taskId: claimed.taskId,
                workUnitId: claimed.workUnitId,
                workerLabel: slot.label,
                taskName: "Objective Worker \(slot.label)"
            )
            throw error
        }
    }

    private func buildMissionRequest(
        for claimed: ClaimedWork,
        workerLabel: String,
        serverSnapshotsContext: String,
        resolvedParentGoal: String?
    ) -> AgentTaskRunner.Request {
        // `resolveParentObjectiveGoal` already merges webhook payload + API; nil means no goal string anywhere.
        let effectiveGoal = resolvedParentGoal
        let userMessage = objectiveBoardUserMessage(
            effectiveGoal: effectiveGoal,
            rootTaskDescription: claimed.payload.rootTaskDescription,
            workUnitDescription: claimed.payload.workDescription,
            objectiveId: claimed.objectiveId,
            taskId: claimed.taskId,
            isSynthesis: claimed.workType == Constants.synthesisType
        )
        let systemPrompt: String
        switch claimed.workType {
        case Constants.synthesisType:
            let completedSummary = (try? completedSummaries(objectiveId: claimed.objectiveId, taskId: claimed.taskId)) ?? []
            let workSummary = completedSummary.isEmpty
                ? "No completed research work units were summarized."
                : completedSummary.map { "- \($0)" }.joined(separator: "\n")
            let context = objectiveContextBlock(
                goal: effectiveGoal,
                taskLine: claimed.payload.rootTaskDescription
            )
            systemPrompt = """
            AgentKVT objective-board mode (tools required). Do not reply with generic chat-assistant disclaimers; you already have the mission in the user message.

            You are \(workerLabel), the synthesis agent for one objective task.

            \(context)

            Synthesis work unit: \(claimed.payload.workDescription)
            Objective ID: \(claimed.objectiveId.uuidString)
            Task ID: \(claimed.taskId.uuidString)
            Work Unit ID: \(claimed.workUnitId.uuidString)

            Authoritative findings already on the server (Postgres) — base your synthesis primarily on these:
            \(serverSnapshotsContext)

            Completed research work units (local summaries, may overlap or add nuance):
            \(workSummary)

            ANTI-HALLUCINATION:
            - You already have an assigned objective and task IDs above. Never claim you lack instructions, missions, or predefined goals.
            - Your final plain-text reply must summarize concrete findings for the traveler (logistics, dates, safety, options) — not meta-commentary about your role.
            - Your final system response MUST be plain English prose sentences. Do NOT begin your message with `{` or `[`.

            Instructions:
            1. Prefer reconciling and summarizing the server findings above; use read_objective_snapshot if you need a fresher list mid-run.
            1a. Call list_dropzone_files first — if any user-uploaded files are relevant to this objective, read them with read_dropzone_file and incorporate that context before searching the web.
            2. Use multi_step_search only if you need one last current fact to close a gap.
            3. Write at least one final objective snapshot with write_objective_snapshot using:
               - objective_id: \(claimed.objectiveId.uuidString)
               - task_id: \(claimed.taskId.uuidString)
               - key: \(finalSummaryKey(taskId: claimed.taskId))
               - value: concise plain-language synthesis (not JSON) of the best guidance
               - mark_task_completed: true
            4. You may write additional supporting snapshots before the final one.
            5. Finish with a short, plain-language summary of what the team found (must be substantive, not a refusal).
            """
        default:
            let context = objectiveContextBlock(
                goal: effectiveGoal,
                taskLine: claimed.payload.rootTaskDescription
            )
            systemPrompt = """
            AgentKVT objective-board mode (tools required). Do not reply with generic chat-assistant disclaimers; you already have the mission in the user message.

            You are \(workerLabel), one member of a parallel objective research team.

            CRITICAL OUTPUT RULES (llama3.2 strict mode):
            - NEVER write JSON, tool-call syntax, or any structured data as a snapshot value.
            - NEVER output {"tool_calls": ...} or similar structures as text.
            - Your final textual response MUST be plain English prose sentences. Do NOT begin your message with `{` or `[`.
            - To call a tool, use the tool interface; do not write tool-call JSON in your response text.

            \(context)

            Focused work unit: \(claimed.payload.workDescription)
            Objective ID: \(claimed.objectiveId.uuidString)
            Task ID: \(claimed.taskId.uuidString)
            Work Unit ID: \(claimed.workUnitId.uuidString)

            Shared knowledge on the server when this work unit started (avoid duplicating these findings):
            \(serverSnapshotsContext)

            Do not claim you lack missions or goals — this work unit is your assigned task.

            Instructions:
            1. Call read_objective_snapshot with objective_id \(claimed.objectiveId.uuidString) (and task_id \(claimed.taskId.uuidString) if you need an updated list) before spending tokens on overlapping searches.
            1a. Call list_dropzone_files — if any user-uploaded files are relevant to this work unit, read them with read_dropzone_file and treat their contents as authoritative user-provided context.
            2. Use multi_step_search to research gaps or updates for this focused subproblem.
            3. Write 1-3 objective snapshots that capture durable findings from this work unit. Each value must be human-readable prose sentences — NOT JSON, NOT tool-call format.
            4. Every snapshot from this work unit must include:
               - objective_id: \(claimed.objectiveId.uuidString)
               - task_id: \(claimed.taskId.uuidString)
               - mark_task_completed: false
            5. Do not mark the overall task complete from this work unit.
            6. Finish with a short summary of the strongest findings you gathered.
            """
        }

        return AgentTaskRunner.Request(
            id: claimed.workUnitId,
            taskName: "Objective Work Unit: \(claimed.title.prefix(60))",
            systemPrompt: systemPrompt,
            triggerSchedule: "objective_board",
            allowedToolIds: ["read_objective_snapshot", "multi_step_search", "write_objective_snapshot", "list_dropzone_files", "read_dropzone_file"],
            ownerProfileId: nil,
            isEnabled: true,
            lastRunAt: nil,
            executionMetadata: .init(
                objectiveId: claimed.objectiveId,
                taskId: claimed.taskId,
                workUnitId: claimed.workUnitId,
                workerLabel: workerLabel
            ),
            userMessageOverride: userMessage
        )
    }

    /// Prefer webhook-stored goal; otherwise load `goal` from the Rails API so older SwiftData work units still ground the model.
    private func resolveParentObjectiveGoal(
        payload: ObjectiveWorkPayload,
        objectiveId: UUID
    ) async -> String? {
        if let g = normalizedGoal(payload.parentObjectiveGoal) { return g }
        guard let backendClient else { return nil }
        do {
            let objective = try await backendClient.fetchObjective(id: objectiveId)
            return normalizedGoal(objective.goal)
        } catch {
            return nil
        }
    }

    private func normalizedGoal(_ raw: String?) -> String? {
        let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !t.isEmpty else { return nil }
        return t
    }

    /// Repeats the mission in the **user** turn — local models (e.g. Llama with tools) often under-weight `system` alone.
    private func objectiveBoardUserMessage(
        effectiveGoal: String?,
        rootTaskDescription: String,
        workUnitDescription: String,
        objectiveId: UUID,
        taskId: UUID,
        isSynthesis: Bool
    ) -> String {
        let goalBlock: String = {
            guard let g = effectiveGoal, !g.isEmpty else {
                return """
                PARENT OBJECTIVE: (not available from local payload — still use TASK FOCUS and WORK UNIT below; call read_objective_snapshot if you need stored context.)
                """
            }
            let capped = g.count > 12_000 ? String(g.prefix(12_000)) + "\n… (truncated)" : g
            return """
            PARENT OBJECTIVE (authoritative full goal):
            \(capped)
            """
        }()

        let synthesisNote = isSynthesis
            ? "This is the SYNTHESIS step: merge findings, call write_objective_snapshot with mark_task_completed true on the final summary key, and write substantive traveler guidance."
            : "This is a RESEARCH step: call read_objective_snapshot, multi_step_search as needed, write_objective_snapshot (mark_task_completed false)."

        return """
        \(goalBlock)

        TASK FOCUS (this task row on the objective):
        \(rootTaskDescription)

        WORK UNIT YOU MUST EXECUTE NOW:
        \(workUnitDescription)

        \(synthesisNote)

        objective_id=\(objectiveId.uuidString)
        task_id=\(taskId.uuidString)

        You MUST use the allowed tools. A plain-text reply that refuses, claims you have no instructions, or only offers to help "in general" is invalid — you already have the goal and work unit above.
        """
    }

    private func createResearchRound(
        objectiveId: UUID,
        taskId: UUID,
        rootTaskDescription: String,
        parentObjectiveGoal: String?,
        planningRound: Int,
        completedSummaries: [String]
    ) async -> Int {
        let planned = await planResearchWorkUnits(
            rootTaskDescription: rootTaskDescription,
            parentObjectiveGoal: parentObjectiveGoal,
            completedSummaries: completedSummaries,
            planningRound: planningRound
        )

        var created = 0
        for title in planned {
            do {
                _ = try createWorkUnit(
                    objectiveId: objectiveId,
                    taskId: taskId,
                    title: title,
                    workType: Constants.researchType,
                    activePhaseHint: "research_round_\(planningRound)",
                    planningRound: planningRound,
                    rootTaskDescription: rootTaskDescription,
                    parentObjectiveGoal: parentObjectiveGoal,
                    priority: planningRound == 1 ? 1.0 : 0.9
                )
                created += 1
            } catch {
                await logEvent(
                    phase: "error",
                    content: "Failed to create work unit '\(title)': \(error)",
                    objectiveId: objectiveId,
                    taskId: taskId,
                    taskName: "Objective Supervisor"
                )
            }
        }

        if created > 0 {
            await logEvent(
                phase: "objective_supervisor",
                content: "Queued \(created) research work unit(s) for round \(planningRound).",
                objectiveId: objectiveId,
                taskId: taskId,
                taskName: "Objective Supervisor"
            )
        }

        return created
    }

    private func planResearchWorkUnits(
        rootTaskDescription: String,
        parentObjectiveGoal: String?,
        completedSummaries: [String],
        planningRound: Int
    ) async -> [String] {
        let summaries = completedSummaries.isEmpty
            ? "None yet."
            : completedSummaries.map { "- \($0)" }.joined(separator: "\n")
        let systemPrompt = """
        You decompose one objective task into parallel stigmergic board work units.
        Respond with ONLY valid JSON in one of these shapes:
        {"work_units":["Task A","Task B"]}
        or
        ["Task A","Task B"]

        Rules:
        - Return 0 to 4 work units.
        - Each work unit must be a concrete research subproblem.
        - Do not repeat completed work.
        - Keep each string under 120 characters.
        """
        let goalBlock: String = {
            let g = parentObjectiveGoal?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if g.isEmpty { return "" }
            return """

            Parent objective (full user goal):
            \(g)
            """
        }()
        let userPrompt = """
        Objective task:
        \(rootTaskDescription)
        \(goalBlock)

        Planning round: \(planningRound)

        Already completed work:
        \(summaries)
        """

        do {
            let response = try await client.chat(
                messages: [
                    .init(role: "system", content: systemPrompt, toolCalls: nil),
                    .init(role: "user", content: userPrompt, toolCalls: nil)
                ],
                tools: nil
            )
            return normalizePlannedWorkUnits(response.content)
        } catch {
            return heuristicWorkUnits(from: rootTaskDescription, planningRound: planningRound, completedSummaries: completedSummaries)
        }
    }

    private func normalizePlannedWorkUnits(_ raw: String?) -> [String] {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return []
        }
        let normalized = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = normalized.data(using: .utf8) else { return [] }
        if let plan = try? JSONDecoder().decode(WorkPlan.self, from: data) {
            return sanitizePlannedTitles(plan.workUnits)
        }
        if let array = try? JSONDecoder().decode([String].self, from: data) {
            return sanitizePlannedTitles(array)
        }
        return []
    }

    private func heuristicWorkUnits(
        from rootTaskDescription: String,
        planningRound: Int,
        completedSummaries: [String]
    ) -> [String] {
        let base = rootTaskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return [] }

        if planningRound == 1 {
            return sanitizePlannedTitles([
                "Research logistics and costs for: \(base)",
                "Identify risks, deadlines, and constraints for: \(base)",
                "Find the strongest recommendations and alternatives for: \(base)"
            ])
        }

        guard !completedSummaries.isEmpty else { return [] }
        return sanitizePlannedTitles([
            "Follow up on unresolved gaps or tradeoffs from: \(base)"
        ])
    }

    private func sanitizePlannedTitles(_ titles: [String]) -> [String] {
        var seen: Set<String> = []
        return titles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { String($0.prefix(120)) }
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(4)
            .map { $0 }
    }

    private func ensureRootWorkUnit(
        objectiveId: UUID,
        taskId: UUID,
        title: String,
        parentObjectiveGoal: String?
    ) throws -> WorkUnit {
        let context = freshContext()
        if let existing = try objectiveWorkUnits(in: context, objectiveId: objectiveId, taskId: taskId)
            .first(where: { $0.workType == Constants.rootType }) {
            return existing
        }

        let payload = ObjectiveWorkPayload(
            objectiveId: objectiveId,
            taskId: taskId,
            rootTaskDescription: title,
            parentObjectiveGoal: parentObjectiveGoal,
            workDescription: title,
            planningRound: 0,
            workType: Constants.rootType,
            resultSummary: nil,
            lastError: nil
        )
        let root = WorkUnit(
            title: title,
            category: Constants.objectiveCategory,
            objectiveId: objectiveId,
            sourceTaskId: taskId,
            workType: Constants.rootType,
            state: WorkUnitState.pending.rawValue,
            moundPayload: encodePayload(payload),
            activePhaseHint: "queued",
            priority: 1.2,
            lastHeartbeatAt: Date()
        )
        context.insert(root)
        try context.save()
        return root
    }

    private func ensureSynthesisWorkUnit(
        objectiveId: UUID,
        taskId: UUID,
        rootTaskDescription: String,
        parentObjectiveGoal: String?
    ) throws -> WorkUnit {
        let context = freshContext()
        if let existing = try objectiveWorkUnits(in: context, objectiveId: objectiveId, taskId: taskId)
            .first(where: { $0.workType == Constants.synthesisType }) {
            return existing
        }
        let title = "Synthesize findings and close out the task"
        let payload = ObjectiveWorkPayload(
            objectiveId: objectiveId,
            taskId: taskId,
            rootTaskDescription: rootTaskDescription,
            parentObjectiveGoal: parentObjectiveGoal,
            workDescription: title,
            planningRound: 99,
            workType: Constants.synthesisType,
            resultSummary: nil,
            lastError: nil
        )
        let workUnit = WorkUnit(
            title: title,
            category: Constants.objectiveCategory,
            objectiveId: objectiveId,
            sourceTaskId: taskId,
            workType: Constants.synthesisType,
            state: WorkUnitState.pending.rawValue,
            moundPayload: encodePayload(payload),
            activePhaseHint: "synthesis",
            priority: 2.0,
            lastHeartbeatAt: Date()
        )
        context.insert(workUnit)
        try context.save()
        return workUnit
    }

    @discardableResult
    private func createWorkUnit(
        objectiveId: UUID,
        taskId: UUID,
        title: String,
        workType: String,
        activePhaseHint: String,
        planningRound: Int,
        rootTaskDescription: String,
        parentObjectiveGoal: String?,
        priority: Double
    ) throws -> WorkUnit {
        let context = freshContext()
        let payload = ObjectiveWorkPayload(
            objectiveId: objectiveId,
            taskId: taskId,
            rootTaskDescription: rootTaskDescription,
            parentObjectiveGoal: parentObjectiveGoal,
            workDescription: title,
            planningRound: planningRound,
            workType: workType,
            resultSummary: nil,
            lastError: nil
        )
        let workUnit = WorkUnit(
            title: title,
            category: Constants.objectiveCategory,
            objectiveId: objectiveId,
            sourceTaskId: taskId,
            workType: workType,
            state: WorkUnitState.pending.rawValue,
            moundPayload: encodePayload(payload),
            activePhaseHint: activePhaseHint,
            priority: priority,
            lastHeartbeatAt: Date()
        )
        context.insert(workUnit)
        try context.save()
        return workUnit
    }

    private func claimNextWorkUnit(slot: ObjectiveWorkerSlot) throws -> ClaimedWork? {
        claimLock.lock()
        defer { claimLock.unlock() }

        let context = freshContext()
        try requeueExpiredClaims(in: context)

        guard let unit = try objectiveBoardUnits(in: context)
            .first(where: {
                $0.workType != Constants.rootType &&
                $0.state == WorkUnitState.pending.rawValue
            }) else {
            return nil
        }

        unit.state = WorkUnitState.inProgress.rawValue
                unit.claimedUntil = Date().addingTimeInterval(90)
        unit.workerLabel = slot.label
        unit.lastHeartbeatAt = Date()
        unit.updatedAt = Date()
        try context.save()

        let payload = decodePayload(unit.moundPayload) ?? ObjectiveWorkPayload(
            objectiveId: unit.objectiveId ?? UUID(),
            taskId: unit.sourceTaskId ?? UUID(),
            rootTaskDescription: unit.title,
            parentObjectiveGoal: nil,
            workDescription: unit.title,
            planningRound: 0,
            workType: unit.workType,
            resultSummary: nil,
            lastError: nil
        )
        guard let objectiveId = unit.objectiveId, let taskId = unit.sourceTaskId else { return nil }
        return ClaimedWork(
            workUnitId: unit.id,
            objectiveId: objectiveId,
            taskId: taskId,
            title: unit.title,
            workType: unit.workType,
            activePhaseHint: unit.activePhaseHint,
            payload: payload
        )
    }

    private func completeWorkUnit(_ workUnitId: UUID, summary: String) throws {
        let context = freshContext()
        guard let unit = try fetchWorkUnit(workUnitId, in: context) else { return }
        unit.state = WorkUnitState.done.rawValue
        unit.claimedUntil = nil
        unit.updatedAt = Date()
        unit.lastHeartbeatAt = Date()
        if var payload = decodePayload(unit.moundPayload) {
            payload.resultSummary = String(summary.prefix(600))
            unit.moundPayload = encodePayload(payload)
        }
        try context.save()
    }

    private func blockWorkUnit(_ workUnitId: UUID, error: String) throws {
        let context = freshContext()
        guard let unit = try fetchWorkUnit(workUnitId, in: context) else { return }
        unit.state = WorkUnitState.blocked.rawValue
        unit.claimedUntil = nil
        unit.updatedAt = Date()
        unit.lastHeartbeatAt = Date()
        if var payload = decodePayload(unit.moundPayload) {
            payload.lastError = String(error.prefix(600))
            unit.moundPayload = encodePayload(payload)
        }
        try context.save()
    }

    private func resetWorkUnitToPending(_ workUnitId: UUID, reason: String) throws {
        let context = freshContext()
        guard let unit = try fetchWorkUnit(workUnitId, in: context) else { return }
        unit.state = WorkUnitState.pending.rawValue
        unit.claimedUntil = nil
        unit.workerLabel = nil
        unit.activePhaseHint = "retry"
        unit.updatedAt = Date()
        if var payload = decodePayload(unit.moundPayload) {
            payload.lastError = String(reason.prefix(600))
            payload.retryCount = (payload.retryCount ?? 0) + 1
            unit.moundPayload = encodePayload(payload)
        }
        try context.save()
    }

    private func touchWorkUnit(
        workUnitId: UUID,
        workerId: UUID,
        workerLabel: String,
        phase: String
    ) throws {
        let context = freshContext()
        guard let unit = try fetchWorkUnit(workUnitId, in: context) else { return }
                unit.claimedUntil = Date().addingTimeInterval(90)
        unit.workerLabel = workerLabel
        unit.activePhaseHint = phase
        unit.lastHeartbeatAt = Date()
        unit.updatedAt = Date()
        try context.save()
    }

    private func updateRootState(rootId: UUID, state: String, phase: String) throws {
        let context = freshContext()
        guard let root = try fetchWorkUnit(rootId, in: context) else { return }
        root.state = state
        root.activePhaseHint = phase
        root.lastHeartbeatAt = Date()
        root.updatedAt = Date()
        try context.save()
    }

    private func waitForResearchToSettle(
        objectiveId: UUID,
        taskId: UUID,
        timeout: TimeInterval? = nil
    ) async throws {
        let timeoutSeconds = timeout ?? researchSettleTimeoutSeconds
        let startedAt = Date()
        while true {
            let context = freshContext()
            try requeueExpiredClaims(in: context)
            let remaining = try objectiveWorkUnits(in: context, objectiveId: objectiveId, taskId: taskId)
                .filter {
                    $0.workType == Constants.researchType &&
                    ($0.state == WorkUnitState.pending.rawValue || $0.state == WorkUnitState.inProgress.rawValue)
                }
            if remaining.isEmpty { return }
            if Date().timeIntervalSince(startedAt) >= timeoutSeconds {
                let detail = try handleResearchTimeout(objectiveId: objectiveId, taskId: taskId, timeout: timeoutSeconds)
                throw NSError(
                    domain: "ObjectiveExecution",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: detail]
                )
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// Marks long-running research as timed out so the supervisor cannot wait forever after
    /// restarts or silent worker failures.
    private func handleResearchTimeout(
        objectiveId: UUID,
        taskId: UUID,
        timeout: TimeInterval
    ) throws -> String {
        let context = freshContext()
        let units = try objectiveWorkUnits(in: context, objectiveId: objectiveId, taskId: taskId)
        let root = units.first(where: { $0.workType == Constants.rootType })
        let trimmedRootTitle = root?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let objectiveName = trimmedRootTitle.isEmpty
            ? "Objective \(objectiveId.uuidString.prefix(8))"
            : trimmedRootTitle
        let timeoutMessage = "Research phase timed out after \(Int(timeout)) seconds without settling."

        for unit in units where unit.workType == Constants.researchType &&
            (unit.state == WorkUnitState.pending.rawValue || unit.state == WorkUnitState.inProgress.rawValue) {
            unit.state = WorkUnitState.blocked.rawValue
                        unit.claimedUntil = nil
            unit.workerLabel = nil
            unit.activePhaseHint = "timed_out"
            unit.updatedAt = Date()
            unit.lastHeartbeatAt = Date()
            if var payload = decodePayload(unit.moundPayload) {
                payload.lastError = timeoutMessage
                unit.moundPayload = encodePayload(payload)
            }
        }
        if let root {
            root.state = WorkUnitState.blocked.rawValue
            root.activePhaseHint = "timed_out"
            root.updatedAt = Date()
            root.lastHeartbeatAt = Date()
        }
        try context.save()

        let actionTitle = "Agent Stalled: \(objectiveName) timed out."
        createLocalActionItem(title: actionTitle, detail: timeoutMessage)
        Task.detached(priority: .utility) { [weak self] in
            await self?.logEvent(
                phase: "error",
                content: actionTitle,
                objectiveId: objectiveId,
                taskId: taskId,
                taskName: "Objective Supervisor"
            )
        }
        return actionTitle
    }

    private func createLocalActionItem(title: String, detail: String) {
        let context = freshContext()
        let payloadData: Data? = try? JSONSerialization.data(
            withJSONObject: [
                "reminderTitle": title,
                "notes": detail
            ],
            options: []
        )
        let item = ActionItem(
            title: title,
            systemIntent: SystemIntent.reminderAdd.rawValue,
            payloadData: payloadData
        )
        context.insert(item)
        try? context.save()
    }

    private func waitForSynthesisToSettle(objectiveId: UUID, taskId: UUID) async throws {
        while true {
            let context = freshContext()
            try requeueExpiredClaims(in: context)
            let synthesisUnits = try objectiveWorkUnits(in: context, objectiveId: objectiveId, taskId: taskId)
                .filter { $0.workType == Constants.synthesisType }
            if let blocked = synthesisUnits.first(where: { $0.state == WorkUnitState.blocked.rawValue }) {
                let detail = decodePayload(blocked.moundPayload)?.lastError ?? "synthesis work unit blocked"
                throw NSError(
                    domain: "ObjectiveExecution",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: detail]
                )
            }
            let remaining = synthesisUnits.filter {
                $0.state == WorkUnitState.pending.rawValue || $0.state == WorkUnitState.inProgress.rawValue
            }
            if remaining.isEmpty { return }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func completedSummaries(objectiveId: UUID, taskId: UUID) throws -> [String] {
        let context = freshContext()
        return try objectiveWorkUnits(in: context, objectiveId: objectiveId, taskId: taskId)
            .filter { $0.workType == Constants.researchType && $0.state == WorkUnitState.done.rawValue }
            .compactMap { decodePayload($0.moundPayload)?.resultSummary }
            .filter { !$0.isEmpty }
    }

    /// Snapshot rows from Postgres (same filter as `read_objective_snapshot`) for prompts.
    private func fetchServerSnapshotsContext(objectiveId: UUID, taskId: UUID) async -> String {
        guard let backendClient else {
            return "Backend client unavailable — use read_objective_snapshot after it is configured."
        }
        do {
            let snapshots = try await backendClient.fetchResearchSnapshots(objectiveId: objectiveId, taskId: taskId)
            if snapshots.isEmpty {
                return "No snapshots stored yet for this objective/task scope."
            }
            let lines = snapshots.prefix(50).map { snap in
                let scope = snap.taskId.map { " [task: \(String($0.uuidString.prefix(8)))…]" } ?? " [objective-wide]"
                return "- \(snap.key)\(scope): \(snap.value)"
            }
            var text = lines.joined(separator: "\n")
            if text.count > 12_000 {
                text = String(text.prefix(12_000)) + "\n… (truncated)"
            }
            return text
        } catch {
            return "Could not load server snapshots (\(error.localizedDescription)). Call read_objective_snapshot to fetch manually."
        }
    }

    private func freshContext() -> ModelContext {
        ModelContext(modelContainer)
    }

    private func objectiveBoardUnits(in context: ModelContext) throws -> [WorkUnit] {
        let category = Constants.objectiveCategory
        let descriptor = FetchDescriptor<WorkUnit>(
            predicate: #Predicate<WorkUnit> { $0.category == category },
            sortBy: [SortDescriptor(\.priority, order: .reverse), SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    private func objectiveWorkUnits(in context: ModelContext, objectiveId: UUID, taskId: UUID) throws -> [WorkUnit] {
        try objectiveBoardUnits(in: context).filter { $0.objectiveId == objectiveId && $0.sourceTaskId == taskId }
    }

    private func fetchWorkUnit(_ id: UUID, in context: ModelContext) throws -> WorkUnit? {
        try objectiveBoardUnits(in: context).first(where: { $0.id == id })
    }

    private func requeueExpiredClaims(in context: ModelContext) throws {
        let now = Date()
        var didChange = false
        for unit in try objectiveBoardUnits(in: context) where unit.state == WorkUnitState.inProgress.rawValue {
            if let claimedUntil = unit.claimedUntil, claimedUntil < now {
                unit.state = WorkUnitState.pending.rawValue
                                unit.claimedUntil = nil
                unit.workerLabel = nil
                unit.activePhaseHint = "requeued"
                unit.updatedAt = now
                didChange = true
            }
        }
        if didChange {
            try context.save()
        }
    }

    // MARK: - Startup orphan recovery

    /// Scans SwiftData for (objectiveId, taskId) groups that have at least one research work unit
    /// but no synthesis work unit. These are objectives whose supervisor task was lost when the app
    /// last restarted mid-execution. Called once at startup; safe to call again (idempotent).
    func findOrphanedObjectiveGroups() -> [OrphanedObjectiveGroup] {
        let context = freshContext()
        guard let allUnits = try? objectiveBoardUnits(in: context) else { return [] }

        // Group non-root work units by (objectiveId, taskId).
        var groups: [String: [WorkUnit]] = [:]
        for unit in allUnits where unit.workType != Constants.rootType {
            guard let objId = unit.objectiveId, let taskId = unit.sourceTaskId else { continue }
            let key = "\(objId.uuidString)/\(taskId.uuidString)"
            groups[key, default: []].append(unit)
        }

        var orphans: [OrphanedObjectiveGroup] = []
        for (_, units) in groups {
            let hasSynthesis = units.contains { $0.workType == Constants.synthesisType }
            let researchUnits = units.filter { $0.workType == Constants.researchType }
            guard !researchUnits.isEmpty, !hasSynthesis else { continue }

            guard let firstUnit = researchUnits.first,
                  let objId = firstUnit.objectiveId,
                  let taskId = firstUnit.sourceTaskId,
                  let payload = decodePayload(firstUnit.moundPayload) else { continue }

            orphans.append(OrphanedObjectiveGroup(
                objectiveId: objId,
                taskId: taskId,
                rootTaskDescription: payload.rootTaskDescription,
                parentObjectiveGoal: payload.parentObjectiveGoal
            ))
        }
        return orphans
    }

    /// Recovery supervisor: waits for any in-flight research to settle, creates the synthesis
    /// work unit, then waits for synthesis to complete. Mirrors the tail of `superviseObjective`.
    func resumeFromSynthesis(orphan: OrphanedObjectiveGroup) async {
        await logEvent(
            phase: "objective_supervisor",
            content: "Recovery supervisor started — resuming synthesis for orphaned task: \(orphan.rootTaskDescription)",
            objectiveId: orphan.objectiveId,
            taskId: orphan.taskId,
            taskName: "Objective Recovery Supervisor"
        )
        do {
            try await waitForResearchToSettle(objectiveId: orphan.objectiveId, taskId: orphan.taskId)
            _ = try ensureSynthesisWorkUnit(
                objectiveId: orphan.objectiveId,
                taskId: orphan.taskId,
                rootTaskDescription: orphan.rootTaskDescription,
                parentObjectiveGoal: orphan.parentObjectiveGoal
            )
            try await waitForSynthesisToSettle(objectiveId: orphan.objectiveId, taskId: orphan.taskId)

            let context = freshContext()
            if let root = (try? objectiveWorkUnits(in: context, objectiveId: orphan.objectiveId, taskId: orphan.taskId))?
                .first(where: { $0.workType == Constants.rootType }) {
                try? updateRootState(rootId: root.id, state: WorkUnitState.done.rawValue, phase: "complete")
            }

            await logEvent(
                phase: "objective_supervisor",
                content: "Recovery supervisor completed synthesis for task: \(orphan.rootTaskDescription)",
                objectiveId: orphan.objectiveId,
                taskId: orphan.taskId,
                taskName: "Objective Recovery Supervisor"
            )
        } catch {
            await logEvent(
                phase: "error",
                content: "Recovery supervisor failed: \(error)",
                objectiveId: orphan.objectiveId,
                taskId: orphan.taskId,
                taskName: "Objective Recovery Supervisor"
            )
        }
    }

    private func encodePayload(_ payload: ObjectiveWorkPayload) -> Data? {
        try? JSONEncoder().encode(payload)
    }

    private func decodePayload(_ data: Data?) -> ObjectiveWorkPayload? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(ObjectiveWorkPayload.self, from: data)
    }

    private func finalSummaryKey(taskId: UUID) -> String {
        "task_summary_\(taskId.uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
    }

    private func objectiveContextBlock(goal: String?, taskLine: String) -> String {
        let g = goal?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if g.isEmpty {
            return "Task focus:\n\(taskLine)"
        }
        return """
        Parent objective (authoritative user goal):
        \(g)

        Your task focus (work within this scope):
        \(taskLine)
        """
    }

    private func looksLikeMetaRefusal(_ text: String) -> Bool {
        MetaRefusalText.isLikelyRefusal(text)
    }

    private func logEvent(
        phase: String,
        content: String,
        objectiveId: UUID?,
        taskId: UUID?,
        workUnitId: UUID? = nil,
        workerLabel: String? = nil,
        taskName: String? = nil
    ) async {
        print("[ObjectiveExecutionPool] [\(workerLabel ?? "Supervisor")] [\(phase)] task=\(taskId?.uuidString ?? "nil"): \(content)")
        guard let backendClient else { return }

        var metadata: [String: String] = [:]
        if let objectiveId {
            metadata["objective_id"] = objectiveId.uuidString
        }
        if let taskId {
            metadata["task_id"] = taskId.uuidString
        }
        if let workUnitId {
            metadata["work_unit_id"] = workUnitId.uuidString
        }
        if let workerLabel, !workerLabel.isEmpty {
            metadata["worker_label"] = workerLabel
        }

        _ = try? await backendClient.createAgentLog(
            taskName: taskName,
            phase: phase,
            content: content,
            metadata: metadata
        )
    }
}
