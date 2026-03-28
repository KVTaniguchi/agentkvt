import Foundation
import ManagerCore
import SwiftData

/// Runs a single mission: invokes the LLM with the mission's prompt and allowed tools,
/// then writes outcome to AgentLog. ActionItems are written by tools (e.g. write_action_item).
public final class MissionRunner: @unchecked Sendable {
    public struct Request: Sendable {
        public let id: UUID
        public let missionName: String
        public let systemPrompt: String
        public let triggerSchedule: String
        public let allowedToolIds: [String]
        public let ownerProfileId: UUID?
        public let isEnabled: Bool
        public let lastRunAt: Date?

        public init(
            id: UUID,
            missionName: String,
            systemPrompt: String,
            triggerSchedule: String = "",
            allowedToolIds: [String],
            ownerProfileId: UUID?,
            isEnabled: Bool = true,
            lastRunAt: Date? = nil
        ) {
            self.id = id
            self.missionName = missionName
            self.systemPrompt = systemPrompt
            self.triggerSchedule = triggerSchedule
            self.allowedToolIds = allowedToolIds
            self.ownerProfileId = ownerProfileId
            self.isEnabled = isEnabled
            self.lastRunAt = lastRunAt
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
                lastRunAt: mission.lastRunAt
            )
        }
    }

    private let modelContext: ModelContext
    private let client: any OllamaClientProtocol
    private let registry: ToolRegistry
    private let logWriter: any MissionLogWriting

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

    public func run(_ request: Request) async throws {
        let allowedTools = request.allowedToolIds
        let systemPrompt = missionSystemPrompt(
            basePrompt: request.systemPrompt,
            allowedTools: allowedTools
        )
        let userMessage = missionUserMessage(ownerProfileId: request.ownerProfileId)
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
    }

    /// Run one mission and log the outcome.
    public func run(_ mission: MissionDefinition) async throws {
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
        let loop = AgentLoop(client: client, registry: registry, allowedToolIds: allowedToolIds)
        let context = MissionExecutionContext.Context(missionId: request.id, missionName: request.missionName)
        return try await MissionExecutionContext.$current.withValue(context) {
            try await loop.run(systemPrompt: systemPrompt, userMessage: userMessage, maxRounds: maxRounds) { event in
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
                case .toolCallCompleted(let name, let toolResult):
                    phase = "tool_result"
                    content = toolResult
                    toolName = name
                    toolTranscript.append(self.toolTranscriptLine(prefix: "tool_result", name: name, content: toolResult))
                    if name == "write_action_item" { actionItemsCounter.count += 1 }
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
    }

    private func missionSystemPrompt(basePrompt: String, allowedTools: [String]) -> String {
        guard allowedTools.contains("write_action_item") else {
            return basePrompt
        }

        let cardinalityInstruction: String
        if basePrompt.localizedCaseInsensitiveContains("exactly one action item")
            || basePrompt.localizedCaseInsensitiveContains("create one action item")
            || basePrompt.localizedCaseInsensitiveContains("one action per") {
            cardinalityInstruction = "Create exactly one action item unless the mission instructions explicitly require more."
        } else {
            cardinalityInstruction = "Create at least one action item before you finish."
        }

        return """
        \(basePrompt)

        Visible output requirement:
        - This mission is only successful after you call write_action_item.
        - \(cardinalityInstruction)
        - Do not end with plain text only.
        - If you found a concrete URL the user should review, prefer systemIntent "url.open" and include payloadJson with the required URL field.
        - Keep the action item title short, specific, and user-facing.
        """
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
