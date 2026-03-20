import Foundation
import Testing
import SwiftData
import ManagerCore
@testable import AgentKVTMac

@Suite("AgentLoop Recovery & Failure Tests")
struct AgentLoopRecoveryTests {
    
    @Test("AgentLoop safely terminates and logs warning when stuck in an infinite tool loop")
    func infiniteLoopTermination() async throws {
        let (context, _) = try createInMemoryContext()
        let mission = createTestMission()
        let registry = ToolRegistry()
        registry.register(makeWriteActionItemTool(modelContext: context))
        
        // Mock client that always returns a tool call, never stopping
        let infiniteResponses = Array(
            repeating: OllamaClient.Message.assistantWithToolCalls([
                .writeActionItem(title: "Loop", systemIntent: "loop")
            ]), 
            count: 15
        )
        let mockClient = MockOllamaClient(responses: infiniteResponses)
        
        let runner = MissionRunner(modelContext: context, client: mockClient, registry: registry)
        
        // Should not throw, but should terminate due to max rounds
        try await runner.run(mission)
        
        // Look for the max rounds warning in the AgentLog
        let logDesc = FetchDescriptor<AgentLog>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        let logs = try context.fetch(logDesc)
        
        let warningLog = logs.first(where: { $0.phase == "warning" })
        #expect(warningLog != nil, "Expected a warning log for max rounds reached.")
        #expect(warningLog?.content.contains("max rounds") == true)
    }
    
    @Test("MissionRunner safely catches and logs Ollama API outages")
    func apiOutageHandling() async throws {
        let (context, _) = try createInMemoryContext()
        let mission = createTestMission()
        let registry = ToolRegistry()
        
        struct ErrorMockClient: OllamaClientProtocol {
            func chat(messages: [OllamaClient.Message], tools: [OllamaClient.ToolDef]?) async throws -> OllamaClient.Message {
                throw URLError(.badServerResponse)
            }
        }
        
        let errorClient = ErrorMockClient()
        let runner = MissionRunner(modelContext: context, client: errorClient, registry: registry)
        
        // It correctly rethrows the error up to the scheduler
        do {
            try await runner.run(mission)
            Issue.record("Expected runner.run to throw an error")
        } catch {
            // Expected to throw
        }
        
        // Look for the error log generated *before* throwing
        let logDesc = FetchDescriptor<AgentLog>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        let logs = try context.fetch(logDesc)
        
        let errorLog = logs.first(where: { $0.phase == "error" })
        #expect(errorLog != nil, "Expected an error log phase to be written to the database.")
        #expect(errorLog?.content.contains("URLError") == true)
    }
    
    // MARK: - Helpers
    
    private func createInMemoryContext() throws -> (ModelContext, ModelContainer) {
        let schema = Schema([LifeContext.self, MissionDefinition.self, ActionItem.self, AgentLog.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (ModelContext(container), container)
    }
    
    private func createTestMission() -> MissionDefinition {
        MissionDefinition(
            missionName: "Test Mission",
            systemPrompt: "You are testing.",
            triggerSchedule: "webhook",
            allowedMCPTools: ["write_action_item"]
        )
    }
}
