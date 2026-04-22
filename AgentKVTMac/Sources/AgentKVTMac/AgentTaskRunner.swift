import Foundation
import ManagerCore
import SwiftData

/// Runs a single mission: invokes the LLM with the mission's prompt and allowed tools,
/// then writes outcome to AgentLog.
public final class AgentTaskRunner: @unchecked Sendable {
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
        public let taskName: String
        public let systemPrompt: String
        public let triggerSchedule: String
        public let allowedToolIds: [String]
        public let ownerProfileId: UUID?
        public let isEnabled: Bool
        public let lastRunAt: Date?
        public let executionMetadata: ExecutionMetadata?
        /// When set, used as the user message instead of the generic "Execute your mission…" line.
        public let userMessageOverride: String?

        public init(
            id: UUID,
            taskName: String,
            systemPrompt: String,
            triggerSchedule: String = "",
            allowedToolIds: [String],
            ownerProfileId: UUID?,
            isEnabled: Bool = true,
            lastRunAt: Date? = nil,
            executionMetadata: ExecutionMetadata? = nil,
            userMessageOverride: String? = nil
        ) {
            self.id = id
            self.taskName = taskName
            self.systemPrompt = systemPrompt
            self.triggerSchedule = triggerSchedule
            self.allowedToolIds = allowedToolIds
            self.ownerProfileId = ownerProfileId
            self.isEnabled = isEnabled
            self.lastRunAt = lastRunAt
            self.executionMetadata = executionMetadata
            self.userMessageOverride = userMessageOverride
        }

    }

    private let modelContext: ModelContext
    private let client: any OllamaClientProtocol
    private let registry: ToolRegistry
    private let logWriter: any AgentTaskLogWriting
    private let freshDataToolIds: Set<String> = [
        "fetch_bee_ai_context",
        "fetch_email_summaries",
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
        logWriter: (any AgentTaskLogWriting)? = nil
    ) {
        self.modelContext = modelContext
        self.client = client
        self.registry = registry
        self.logWriter = logWriter ?? SwiftDataAgentTaskLogWriter(modelContext: modelContext)
    }

    public func run(_ request: Request) async throws -> String {
        let allowedTools = request.allowedToolIds
        let systemPrompt = taskSystemPrompt(
            basePrompt: request.systemPrompt,
            allowedTools: allowedTools
        )
        let userMessage = request.userMessageOverride ?? taskUserMessage(ownerProfileId: request.ownerProfileId)
        let context = AgentTaskExecutionContext.Context(
            taskName: request.taskName,
            objectiveId: request.executionMetadata?.objectiveId,
            taskId: request.executionMetadata?.taskId,
            workUnitId: request.executionMetadata?.workUnitId,
            workerLabel: request.executionMetadata?.workerLabel
        )
        return try await TokenUsageLogger.$currentTask.withValue(request.taskName) {
            try await AgentTaskExecutionContext.$current.withValue(context) {
                await logWriter.writeLog(
                    taskName: request.taskName,
                    phase: "start",
                    content: "Starting mission with \(allowedTools.count) allowed tool(s): \(allowedTools.joined(separator: ", "))",
                    toolName: nil
                )
                let toolTranscript = ToolTranscriptRecorder()
                let result: String
                do {
                    var first = try await runLoop(
                        request: request,
                        allowedToolIds: allowedTools,
                        systemPrompt: systemPrompt,
                        userMessage: userMessage,
                        toolTranscript: toolTranscript
                    )
                    if let retryNudge = objectiveBoardRetryNudge(request: request, firstOutcome: first, transcript: toolTranscript.entries) {
                        let nudge = userMessage + "\n\n" + retryNudge
                        first = try await runLoop(
                            request: request,
                            allowedToolIds: allowedTools,
                            systemPrompt: systemPrompt,
                            userMessage: nudge,
                            maxRounds: 12,
                            toolTranscript: toolTranscript
                        )
                    }
                    result = first
                } catch {
                    await logWriter.writeLog(
                        taskName: request.taskName,
                        phase: "error",
                        content: "Error: \(error)",
                        toolName: nil
                    )
                    throw error
                }
                return result
            }
        }
    }

    /// Run one mission and log the outcome.

    /// Returns a retry nudge string when the objective-board mission needs a second pass,
    /// or nil if the first pass looks valid. Covers three failure modes:
    /// 1. Refusal boilerplate ("I don't have any specific objective…")
    /// 2. Raw tool-call JSON written as text instead of using the tool API
    /// 3. Model completed research but never called write_objective_snapshot
    private func objectiveBoardRetryNudge(request: Request, firstOutcome: String, transcript: [String]) -> String? {
        guard request.executionMetadata?.objectiveId != nil else { return nil }
        guard request.allowedToolIds.contains("write_objective_snapshot") else { return nil }

        if MetaRefusalText.isInvalidResearchOutput(firstOutcome) {
            return "RETRY (mandatory): Your previous response was invalid - either a generic disclaimer or raw tool-call JSON written as text. You MUST use the tool API to invoke tools. Do NOT write tool_calls JSON in your reply text. Call read_objective_snapshot first via the tool API, then multi_step_search and/or write_objective_snapshot via the tool API."
        }

        let wroteSnapshot = transcript.contains { $0.contains("write_objective_snapshot") }
        if !wroteSnapshot {
            return "RETRY (mandatory): You completed searches but never called write_objective_snapshot. You MUST call write_objective_snapshot now using the tool API to persist your findings. Use objective_id and task_id from your instructions. Do not respond with plain text only."
        }

        return nil
    }

    private func taskUserMessage(ownerProfileId: UUID?) -> String {
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
            case .toolCallCompleted(let name, let toolResult, _):
                phase = "tool_result"
                content = toolResult
                toolName = name
                toolTranscript.append(self.toolTranscriptLine(prefix: "tool_result", name: name, content: toolResult))
            case .finalResponse(let responseContent):
                phase = "assistant_final"
                content = self.assistantResponseContent(responseContent, toolCallCount: 0)
                toolName = nil
            case .maxRoundsReached:
                phase = "warning"
                content = "Agent loop reached max rounds before producing a final response."
                toolName = nil
            }
            await self.logWriter.writeLog(
                taskName: request.taskName,
                phase: phase,
                content: content,
                toolName: toolName
            )
        }
    }

    private func missionToolBatchExecutionPolicy() -> AgentLoop.ToolBatchExecutionPolicy {
        AgentLoop.ToolBatchExecutionPolicy { requestedToolName, batchToolNames in
            return nil
        }
    }

    private func taskSystemPrompt(
        basePrompt: String,
        allowedTools: [String]
    ) -> String {
        let trimmedPrompt = basePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let toolGuidance = runtimeToolGuidance(basePrompt: trimmedPrompt, allowedTools: allowedTools)

        var sections: [String] = []
        if !trimmedPrompt.isEmpty { sections.append(trimmedPrompt) }
        if !toolGuidance.isEmpty { sections.append(toolGuidance) }
        return sections.joined(separator: "\n\n")
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
        case "web_search_and_fetch":
            return """
            web_search_and_fetch guidance:
            - Use this tool for current web information, recent facts, or anything that depends on live pages and matches the mission.
            """
        case "fetch_agent_logs":
            return """
            fetch_agent_logs guidance:
            - Use this tool to inspect recent execution history before drawing conclusions about failures or unexpected output.
            - Filter by mission_name to focus on a specific mission, or omit it to see all recent activity.
            - Use phases: "error,warning" to focus on problems, or "tool_call,tool_result" to trace what the agent actually fetched.
            """
        case "headless_browser_scout":
            return """
            headless_browser_scout guidance:
            - Use this tool when a site needs a real browser, JavaScript execution, or click/fill interactions.
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
        case "ask_gemini":
            return """
            ask_gemini guidance:
            - Prefer this for general knowledge, reasoning, and factual questions that do not require live data: theme park tips, travel planning, financial concepts, product comparisons, historical facts, recommendations, explanations, and summarisation.
            - Call this INSTEAD of web_search or multi_step_search when the question is answerable from broad training knowledge — it is faster and uses no local compute.
            - Reserve web_search and multi_step_search for questions that require current prices, schedules, recent news, or live availability.
            """
        case "multi_step_search":
            return """
            multi_step_search guidance:
            - Use this to run 2–5 related queries in one turn (e.g. compare hotel prices across 3 sites).
            - Pass steps_json with type "search" for web queries or "browse" for specific URLs.
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

    private func toolTranscriptLine(prefix: String, name: String, content: String) -> String {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix) \(name): \(String(normalized.prefix(400)))"
    }
}
