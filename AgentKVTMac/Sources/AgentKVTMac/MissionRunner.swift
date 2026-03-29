import Foundation
import ManagerCore
import SwiftData

/// Runs a single mission: invokes the LLM with the mission's prompt and allowed tools,
/// then writes outcome to AgentLog. ActionItems are written by tools (e.g. write_action_item).
public final class MissionRunner: @unchecked Sendable {
    public struct Request: Sendable {
        public struct ExecutionMetadata: Sendable {
            public let objectiveId: UUID?
            public let taskId: UUID?
            public let workUnitId: UUID?
            public let workerLabel: String?

            public init(
                objectiveId: UUID? = nil,
                taskId: UUID? = nil,
                workUnitId: UUID? = nil,
                workerLabel: String? = nil
            ) {
                self.objectiveId = objectiveId
                self.taskId = taskId
                self.workUnitId = workUnitId
                self.workerLabel = workerLabel
            }
        }

        public let id: UUID
        public let missionName: String
        public let systemPrompt: String
        public let triggerSchedule: String
        public let allowedToolIds: [String]
        public let ownerProfileId: UUID?
        public let isEnabled: Bool
        public let lastRunAt: Date?
        public let executionMetadata: ExecutionMetadata?
        /// Summaries of unhandled actions already created by this mission. Injected into the
        /// system prompt so the LLM avoids creating duplicate suggestions on repeated runs.
        public let existingActionItemSummaries: [String]
        /// When set, used as the user message instead of the generic "Execute your mission…" line.
        public let userMessageOverride: String?

        public init(
            id: UUID,
            missionName: String,
            systemPrompt: String,
            triggerSchedule: String = "",
            allowedToolIds: [String],
            ownerProfileId: UUID?,
            isEnabled: Bool = true,
            lastRunAt: Date? = nil,
            executionMetadata: ExecutionMetadata? = nil,
            existingActionItemSummaries: [String] = [],
            userMessageOverride: String? = nil
        ) {
            self.id = id
            self.missionName = missionName
            self.systemPrompt = systemPrompt
            self.triggerSchedule = triggerSchedule
            self.allowedToolIds = allowedToolIds
            self.ownerProfileId = ownerProfileId
            self.isEnabled = isEnabled
            self.lastRunAt = lastRunAt
            self.executionMetadata = executionMetadata
            self.existingActionItemSummaries = existingActionItemSummaries
            self.userMessageOverride = userMessageOverride
        }

        init(_ mission: MissionDefinition) {
            self.init(
                id: mission.id,
                missionName: mission.missionName,
                systemPrompt: mission.systemPrompt,
                triggerSchedule: mission.triggerSchedule,
                allowedToolIds: mission.allowedMCPTools,
                ownerProfileId: mission.ownerProfileId,
                isEnabled: mission.isEnabled,
                lastRunAt: mission.lastRunAt,
                userMessageOverride: nil
            )
        }

        func with(existingActionItemSummaries: [String]) -> Request {
            Request(
                id: id,
                missionName: missionName,
                systemPrompt: systemPrompt,
                triggerSchedule: triggerSchedule,
                allowedToolIds: allowedToolIds,
                ownerProfileId: ownerProfileId,
                isEnabled: isEnabled,
                lastRunAt: lastRunAt,
                executionMetadata: executionMetadata,
                existingActionItemSummaries: existingActionItemSummaries,
                userMessageOverride: userMessageOverride
            )
        }
    }

    private let modelContext: ModelContext
    private let client: any OllamaClientProtocol
    private let registry: ToolRegistry
    private let logWriter: any MissionLogWriting
    private let freshDataToolIds: Set<String> = [
        "fetch_bee_ai_context",
        "fetch_email_summaries",
        "fetch_mission_status",
        "fetch_work_units",
        "get_life_context",
        "github_agent",
        "headless_browser_scout",
        "incoming_email_trigger",
        "list_dropzone_files",
        "list_resource_health",
        "read_dropzone_file",
        "web_search_and_fetch",
        "multi_step_search",
        "read_research_snapshot"
    ]
    private let deferredVisibleOutputToolIds: Set<String> = ["write_action_item"]

    private final class ActionItemCounter: @unchecked Sendable {
        var count = 0
    }

    private final class ToolTranscriptRecorder: @unchecked Sendable {
        private(set) var entries: [String] = []

        func append(_ entry: String) {
            entries.append(entry)
            if entries.count > 8 {
                entries.removeFirst(entries.count - 8)
            }
        }
    }

    public init(
        modelContext: ModelContext,
        client: any OllamaClientProtocol,
        registry: ToolRegistry,
        logWriter: (any MissionLogWriting)? = nil
    ) {
        self.modelContext = modelContext
        self.client = client
        self.registry = registry
        self.logWriter = logWriter ?? SwiftDataMissionLogWriter(modelContext: modelContext)
    }

    public func run(_ request: Request) async throws -> String {
        let allowedTools = request.allowedToolIds
        let systemPrompt = missionSystemPrompt(
            basePrompt: request.systemPrompt,
            allowedTools: allowedTools,
            existingActionItemSummaries: request.existingActionItemSummaries
        )
        let userMessage = request.userMessageOverride ?? missionUserMessage(ownerProfileId: request.ownerProfileId)
        let context = MissionExecutionContext.Context(
            missionId: request.id,
            missionName: request.missionName,
            objectiveId: request.executionMetadata?.objectiveId,
            taskId: request.executionMetadata?.taskId,
            workUnitId: request.executionMetadata?.workUnitId,
            workerLabel: request.executionMetadata?.workerLabel
        )
        return try await MissionExecutionContext.$current.withValue(context) {
            await logWriter.writeLog(
                missionId: request.id,
                missionName: request.missionName,
                phase: "start",
                content: "Starting mission with \(allowedTools.count) allowed tool(s): \(allowedTools.joined(separator: ", "))",
                toolName: nil
            )
            let actionItemsCounter = ActionItemCounter()
            let toolTranscript = ToolTranscriptRecorder()
            let result: String
            do {
                result = try await runLoop(
                    request: request,
                    allowedToolIds: allowedTools,
                    systemPrompt: systemPrompt,
                    userMessage: userMessage,
                    actionItemsCounter: actionItemsCounter,
                    toolTranscript: toolTranscript
                )
            } catch {
                await logWriter.writeLog(
                    missionId: request.id,
                    missionName: request.missionName,
                    phase: "error",
                    content: "Error: \(error)",
                    toolName: nil
                )
                throw error
            }
            if allowedTools.contains("write_action_item") && actionItemsCounter.count == 0 {
                await logWriter.writeLog(
                    missionId: request.id,
                    missionName: request.missionName,
                    phase: "warning",
                    content: "Mission completed without write_action_item. Attempting one recovery pass to create a visible action item for the user.",
                    toolName: nil
                )
                do {
                    _ = try await runLoop(
                        request: request,
                        allowedToolIds: ["write_action_item"],
                        systemPrompt: recoverySystemPrompt(for: request.missionName),
                        userMessage: recoveryUserMessage(
                            request: request,
                            originalOutcome: result,
                            toolTranscript: toolTranscript.entries
                        ),
                        maxRounds: 3,
                        actionItemsCounter: actionItemsCounter,
                        toolTranscript: toolTranscript
                    )
                } catch {
                    await logWriter.writeLog(
                        missionId: request.id,
                        missionName: request.missionName,
                        phase: "warning",
                        content: "Recovery pass failed while trying to create an action item: \(error)",
                        toolName: nil
                    )
                }
            }
            if allowedTools.contains("write_action_item") && actionItemsCounter.count == 0 {
                await logWriter.writeLog(
                    missionId: request.id,
                    missionName: request.missionName,
                    phase: "warning",
                    content: "Mission completed but write_action_item was never called, even after recovery. No action items were created and the user will see no output.",
                    toolName: nil
                )
            }
            await logWriter.writeLog(
                missionId: request.id,
                missionName: request.missionName,
                phase: "outcome",
                content: result,
                toolName: nil
            )
            return result
        }
    }

    /// Run one mission and log the outcome.
    public func run(_ mission: MissionDefinition) async throws -> String {
        try await run(Request(mission))
    }

    private func missionUserMessage(ownerProfileId: UUID?) -> String {
        var message = "Execute your mission. Use the available tools to create action items or other outputs as defined in your instructions."
        guard let ownerProfileId else {
            return message
        }
        let owner = try? modelContext.fetch(
            FetchDescriptor<FamilyMember>(
                predicate: #Predicate<FamilyMember> { $0.id == ownerProfileId }
            )
        ).first
        if let owner {
            message += " Mission owner profile: \(owner.displayName). Keep outputs grounded in this person's context."
        } else {
            message += " Mission owner profile ID: \(ownerProfileId.uuidString). Keep outputs grounded in this person's context."
        }
        return message
    }

    private func assistantResponseContent(_ content: String?, toolCallCount: Int) -> String {
        let trimmedContent = content?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedContent, !trimmedContent.isEmpty {
            return trimmedContent
        }
        return "Assistant requested \(toolCallCount) tool call(s)."
    }

    private func runLoop(
        request: Request,
        allowedToolIds: [String],
        systemPrompt: String,
        userMessage: String,
        maxRounds: Int = 10,
        actionItemsCounter: ActionItemCounter,
        toolTranscript: ToolTranscriptRecorder
    ) async throws -> String {
        let loop = AgentLoop(
            client: client,
            registry: registry,
            allowedToolIds: allowedToolIds,
            toolBatchExecutionPolicy: missionToolBatchExecutionPolicy()
        )
        return try await loop.run(systemPrompt: systemPrompt, userMessage: userMessage, maxRounds: maxRounds) { event in
            let phase: String
            let content: String
            let toolName: String?
            switch event {
            case .assistantResponse(let responseContent, let toolCalls):
                phase = "assistant"
                content = self.assistantResponseContent(responseContent, toolCallCount: toolCalls.count)
                toolName = nil
            case .toolCallRequested(let name, let arguments):
                phase = "tool_call"
                content = arguments
                toolName = name
                toolTranscript.append(self.toolTranscriptLine(prefix: "tool_call", name: name, content: arguments))
            case .toolCallCompleted(let name, let toolResult, let wasDeferred):
                phase = "tool_result"
                content = toolResult
                toolName = name
                toolTranscript.append(self.toolTranscriptLine(prefix: "tool_result", name: name, content: toolResult))
                if name == "write_action_item" && !wasDeferred { actionItemsCounter.count += 1 }
            case .finalResponse(let responseContent):
                phase = "assistant_final"
                content = responseContent
                toolName = nil
            case .maxRoundsReached:
                phase = "warning"
                content = "Agent loop reached max rounds before producing a final response."
                toolName = nil
            }
            await self.logWriter.writeLog(
                missionId: request.id,
                missionName: request.missionName,
                phase: phase,
                content: content,
                toolName: toolName
            )
        }
    }

    private func missionToolBatchExecutionPolicy() -> AgentLoop.ToolBatchExecutionPolicy {
        AgentLoop.ToolBatchExecutionPolicy { [freshDataToolIds = self.freshDataToolIds, deferredVisibleOutputToolIds = self.deferredVisibleOutputToolIds] requestedToolName, batchToolNames in
            guard deferredVisibleOutputToolIds.contains(requestedToolName) else {
                return nil
            }
            let batchToolSet = Set(batchToolNames)
            guard !batchToolSet.isDisjoint(with: freshDataToolIds) else {
                return nil
            }
            return """
            Deferred: \(requestedToolName) was skipped because this same response also requested fresh data-gathering tools. Review the new tool results and then call \(requestedToolName) in a later response.
            """
        }
    }

    private func missionSystemPrompt(
        basePrompt: String,
        allowedTools: [String],
        existingActionItemSummaries: [String] = []
    ) -> String {
        let trimmedPrompt = basePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let toolGuidance = runtimeToolGuidance(basePrompt: trimmedPrompt, allowedTools: allowedTools)

        var sections: [String] = []
        if !trimmedPrompt.isEmpty { sections.append(trimmedPrompt) }
        if !toolGuidance.isEmpty { sections.append(toolGuidance) }
        if !existingActionItemSummaries.isEmpty {
            let list = existingActionItemSummaries
                .map { Self.sanitizeActionItemTitle($0) }
                .filter { !$0.isEmpty }
                .map { "  - \($0)" }
                .joined(separator: "\n")
            if !list.isEmpty {
                sections.append("""
                Already-pending actions from this mission (the user has not handled these yet — do not create duplicates):
                \(list)
                Only call write_action_item if you have something meaningfully different to surface.
                """)
            }
        }
        return sections.joined(separator: "\n\n")
    }

    /// Strip characters that could be used to inject instructions into the system prompt.
    /// Allows printable ASCII except newlines, carriage returns, and null bytes, then caps length.
    /// This prevents stored action item titles from acting as prompt injection vectors.
    private static func sanitizeActionItemTitle(_ raw: String) -> String {
        let allowed = raw.unicodeScalars.filter { scalar in
            scalar.value >= 0x20 && scalar.value < 0x7F && scalar != "\\"
        }
        let cleaned = String(String.UnicodeScalarView(allowed))
            .trimmingCharacters(in: .whitespaces)
        return String(cleaned.prefix(120))
    }

    private func runtimeToolGuidance(basePrompt: String, allowedTools: [String]) -> String {
        let normalizedToolIds = Array(NSOrderedSet(array: allowedTools)) as? [String] ?? allowedTools
        guard !normalizedToolIds.isEmpty else {
            return ""
        }

        var sections = [
            """
            Runtime tool permissions:
            - The following tools are already authorized for this mission even if the user's prompt does not mention them by name: \(normalizedToolIds.joined(separator: ", ")).
            - Use only tools from this list, and call them whenever they materially help complete the mission.
            """
        ]

        for toolId in normalizedToolIds {
            if let guidance = runtimeToolSection(for: toolId, basePrompt: basePrompt) {
                sections.append(guidance)
            }
        }

        return sections.joined(separator: "\n\n")
    }

    private func runtimeToolSection(for toolId: String, basePrompt: String) -> String? {
        switch toolId {
        case "write_action_item":
            let cardinalityInstruction: String
            if basePrompt.localizedCaseInsensitiveContains("exactly one action item")
                || basePrompt.localizedCaseInsensitiveContains("create one action item")
                || basePrompt.localizedCaseInsensitiveContains("one action per") {
                cardinalityInstruction = "Create exactly one action item unless the mission instructions explicitly require more."
            } else {
                cardinalityInstruction = "Create at least one action item before you finish."
            }

            return """
            write_action_item requirement:
            - This mission is only successful after you call write_action_item.
            - \(cardinalityInstruction)
            - Do not end with plain text only.
            - Use one of these systemIntent values only: calendar.create, mail.reply, reminder.add, url.open.
            - If you found a concrete URL the user should review, prefer systemIntent "url.open" and include payloadJson with the required URL field.
            - Keep the action item title short, specific, and user-facing.
            - If you need fresh information from tools such as web_search_and_fetch or headless_browser_scout, call those tools first, review their results, and only then call write_action_item in a later response.
            """
        case "web_search_and_fetch":
            return """
            web_search_and_fetch guidance:
            - Use this tool for current web information, recent facts, or anything that depends on live pages and matches the mission.
            - Do not call write_action_item in the same response as this search. Search first, then review the fetched results, then create the action item in a later response.
            """
        case "fetch_agent_logs":
            return """
            fetch_agent_logs guidance:
            - Use this tool to inspect recent execution history before drawing conclusions about failures or unexpected output.
            - Filter by mission_name to focus on a specific mission, or omit it to see all recent activity.
            - Use phases: "error,warning" to focus on problems, or "tool_call,tool_result" to trace what the agent actually fetched.
            - After reviewing the logs, surface a write_action_item with a concrete diagnosis or recommended fix.
            """
        case "headless_browser_scout":
            return """
            headless_browser_scout guidance:
            - Use this tool when a site needs a real browser, JavaScript execution, or click/fill interactions.
            - When this tool gathers fresh information, wait for its results before calling write_action_item.
            - Only browse URLs that are directly relevant to the mission's stated topic. If a search result is a job listing, career page, social media profile, news article, or any other page unrelated to the mission's goal, skip it entirely — do not call this tool on it.
            """
        case "send_notification_email":
            return """
            send_notification_email guidance:
            - Use this tool when the mission should deliver a concise alert or summary to the user by email.
            """
        case "fetch_bee_ai_context":
            return """
            fetch_bee_ai_context guidance:
            - Use this tool when recent Bee personal-memory context (conversations, daily brief, facts) would improve prioritization or personalization.
            """
        case "incoming_email_trigger":
            return """
            incoming_email_trigger guidance:
            - Start by reading the pending inbox trigger so your actions stay grounded in the incoming email context.
            """
        case "github_agent":
            return """
            github_agent guidance:
            - Use this tool for read-only GitHub information that is relevant to the mission.
            """
        case "multi_step_search":
            return """
            multi_step_search guidance:
            - Use this to run 2–5 related queries in one turn (e.g. compare hotel prices across 3 sites).
            - Pass steps_json with type "search" for web queries or "browse" for specific URLs.
            - Do not call write_action_item in the same response — review results first.
            """
        case "read_research_snapshot":
            return """
            read_research_snapshot guidance:
            - Call at mission start to retrieve the last known tracked value for a key.
            - If "first check" is returned, fetch the current value then call write_research_snapshot.
            """
        case "write_research_snapshot":
            return """
            write_research_snapshot guidance:
            - Call after observing a current value to persist it and detect meaningful change.
            - Only call write_action_item if the result starts with "changed:".
            """
        case "read_objective_snapshot":
            return """
            read_objective_snapshot guidance:
            - Call early on objective-board work units to load findings already stored on the server for this objective.
            - Pass task_id when the work unit has one so you see objective-wide snapshots plus this task's rows.
            - Skip redundant searches when a key already answers your question; refine or add new keys instead.
            """
        case "write_objective_snapshot":
            return """
            write_objective_snapshot guidance:
            - Persist durable findings as plain-language prose only (never JSON arrays/objects or tool-call blobs).
            - After multi_step_search, synthesize results into concise human-readable lines before writing.
            """
        default:
            guard let description = registry.tool(id: toolId)?.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !description.isEmpty else {
                return nil
            }
            let normalizedDescription = description
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return """
            \(toolId) guidance:
            - \(normalizedDescription)
            """
        }
    }

    private func recoverySystemPrompt(for missionName: String) -> String {
        """
        You are repairing a completed mission named "\(missionName)" that forgot to call write_action_item.
        You must call write_action_item exactly once before you respond with any plain text.
        Use the mission outcome and recent tool transcript to create one useful, visible action item for iOS.
        Prefer systemIntent "url.open" when there is a concrete URL to review and include payloadJson with that URL.
        If no URL is available, use systemIntent "reminder.add" and put the report summary into the reminder notes.
        Keep the title concise and user-facing.
        After the tool call succeeds, reply with one short confirmation sentence.
        """
    }

    private func recoveryUserMessage(
        request: Request,
        originalOutcome: String,
        toolTranscript: [String]
    ) -> String {
        let transcript = toolTranscript.isEmpty
            ? "No prior tool transcript was recorded."
            : toolTranscript.joined(separator: "\n")

        return """
        Original mission prompt:
        \(request.systemPrompt)

        Final mission outcome:
        \(originalOutcome)

        Recent tool transcript:
        \(transcript)

        Create the missing action item now.
        """
    }

    private func toolTranscriptLine(prefix: String, name: String, content: String) -> String {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix) \(name): \(String(normalized.prefix(400)))"
    }
}
