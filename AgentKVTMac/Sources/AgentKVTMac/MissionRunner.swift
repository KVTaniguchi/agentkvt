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
        let loop = AgentLoop(client: client, registry: registry, allowedToolIds: allowedTools)
        let systemPrompt = request.systemPrompt
        let userMessage = missionUserMessage(ownerProfileId: request.ownerProfileId)
        await logWriter.writeLog(
            missionId: request.id,
            missionName: request.missionName,
            phase: "start",
            content: "Starting mission with \(allowedTools.count) allowed tool(s): \(allowedTools.joined(separator: ", "))",
            toolName: nil
        )
        let result: String
        do {
            let context = MissionExecutionContext.Context(missionId: request.id, missionName: request.missionName)
            result = try await MissionExecutionContext.$current.withValue(context) {
                try await loop.run(systemPrompt: systemPrompt, userMessage: userMessage) { event in
                    let details: (phase: String, content: String, toolName: String?) = switch event {
                    case .assistantResponse(let content, let toolCalls):
                        (
                            "assistant",
                            self.assistantResponseContent(content, toolCallCount: toolCalls.count),
                            nil
                        )
                    case .toolCallRequested(let name, let arguments):
                        ("tool_call", arguments, name)
                    case .toolCallCompleted(let name, let result):
                        ("tool_result", result, name)
                    case .finalResponse(let content):
                        ("assistant_final", content, nil)
                    case .maxRoundsReached:
                        ("warning", "Agent loop reached max rounds before producing a final response.", nil)
                    }
                    await self.logWriter.writeLog(
                        missionId: request.id,
                        missionName: request.missionName,
                        phase: details.phase,
                        content: details.content,
                        toolName: details.toolName
                    )
                }
            }
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
}
