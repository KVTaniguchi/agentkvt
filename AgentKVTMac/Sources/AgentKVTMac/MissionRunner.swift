import Foundation
import ManagerCore
import SwiftData

/// Runs a single mission: invokes the LLM with the mission's prompt and allowed tools,
/// then writes outcome to AgentLog. ActionItems are written by tools (e.g. write_action_item).
public final class MissionRunner {
    private let modelContext: ModelContext
    private let client: any OllamaClientProtocol
    private let registry: ToolRegistry

    public init(modelContext: ModelContext, client: any OllamaClientProtocol, registry: ToolRegistry) {
        self.modelContext = modelContext
        self.client = client
        self.registry = registry
    }

    /// Run one mission and log the outcome.
    public func run(_ mission: MissionDefinition) async throws {
        let allowedTools = mission.allowedMCPTools
        let loop = AgentLoop(client: client, registry: registry, allowedToolIds: allowedTools)
        let systemPrompt = mission.systemPrompt
        let userMessage = missionUserMessage(for: mission)
        let startLog = AgentLog(
            missionId: mission.id,
            missionName: mission.missionName,
            phase: "start",
            content: "Starting mission with \(allowedTools.count) allowed tool(s): \(allowedTools.joined(separator: ", "))"
        )
        modelContext.insert(startLog)
        try modelContext.save()
        let result: String
        do {
            let context = MissionExecutionContext.Context(missionId: mission.id, missionName: mission.missionName)
            result = try await MissionExecutionContext.$current.withValue(context) {
                try await loop.run(systemPrompt: systemPrompt, userMessage: userMessage) { [modelContext] event in
                    let log = switch event {
                    case .assistantResponse(let content, let toolCalls):
                        AgentLog(
                            missionId: mission.id,
                            missionName: mission.missionName,
                            phase: "assistant",
                            content: content ?? "Assistant requested \(toolCalls.count) tool call(s)."
                        )
                    case .toolCallRequested(let name, let arguments):
                        AgentLog(
                            missionId: mission.id,
                            missionName: mission.missionName,
                            phase: "tool_call",
                            content: arguments,
                            toolName: name
                        )
                    case .toolCallCompleted(let name, let result):
                        AgentLog(
                            missionId: mission.id,
                            missionName: mission.missionName,
                            phase: "tool_result",
                            content: result,
                            toolName: name
                        )
                    case .finalResponse(let content):
                        AgentLog(
                            missionId: mission.id,
                            missionName: mission.missionName,
                            phase: "assistant_final",
                            content: content
                        )
                    case .maxRoundsReached:
                        AgentLog(
                            missionId: mission.id,
                            missionName: mission.missionName,
                            phase: "warning",
                            content: "Agent loop reached max rounds before producing a final response."
                        )
                    }
                    modelContext.insert(log)
                    try? modelContext.save()
                }
            }
        } catch {
            let log = AgentLog(missionId: mission.id, missionName: mission.missionName, phase: "error", content: "Error: \(error)")
            modelContext.insert(log)
            try modelContext.save()
            throw error
        }
        let log = AgentLog(missionId: mission.id, missionName: mission.missionName, phase: "outcome", content: result)
        modelContext.insert(log)
        try modelContext.save()
    }

    private func missionUserMessage(for mission: MissionDefinition) -> String {
        var message = "Execute your mission. Use the available tools to create action items or other outputs as defined in your instructions."
        guard let ownerProfileId = mission.ownerProfileId else {
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
}
