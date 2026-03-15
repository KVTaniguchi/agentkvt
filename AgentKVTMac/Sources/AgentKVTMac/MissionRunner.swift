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
    /// - Parameter additionalContext: Optional context (e.g. from Dropzone) to prepend to the mission prompt.
    public func run(_ mission: MissionDefinition, additionalContext: String? = nil) async throws {
        let allowedTools = mission.allowedMCPTools
        let loop = AgentLoop(client: client, registry: registry, allowedToolIds: allowedTools)
        let systemPrompt = mission.systemPrompt
        var userMessage = "Execute your mission. Use the available tools to create action items or other outputs as defined in your instructions."
        if let ctx = additionalContext, !ctx.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userMessage = "Additional context from inbound files:\n\n\(ctx)\n\n---\n\n" + userMessage
        }
        let result: String
        do {
            result = try await loop.run(systemPrompt: systemPrompt, userMessage: userMessage)
        } catch {
            let log = AgentLog(missionId: mission.id, missionName: mission.missionName, phase: "outcome", content: "Error: \(error)")
            modelContext.insert(log)
            try modelContext.save()
            throw error
        }
        let log = AgentLog(missionId: mission.id, missionName: mission.missionName, phase: "outcome", content: result)
        modelContext.insert(log)
        try modelContext.save()
    }
}
