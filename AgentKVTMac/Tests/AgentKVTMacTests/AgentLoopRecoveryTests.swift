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
        let request = createTestRequest()
        let registry = ToolRegistry()

        let infiniteResponses = Array(
            repeating: OllamaClient.Message.assistantWithToolCalls([
                .webSearch(query: "infinite loop test")
            ]),
            count: 15
        )
        let mockClient = MockOllamaClient(responses: infiniteResponses)

        let runner = AgentTaskRunner(modelContext: context, client: mockClient, registry: registry)

        _ = try await runner.run(request)

        let logDesc = FetchDescriptor<AgentLog>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        let logs = try context.fetch(logDesc)

        let warningLog = logs.first(where: { $0.phase == "warning" })
        #expect(warningLog != nil, "Expected a warning log for max rounds reached.")
        #expect(warningLog?.content.contains("max rounds") == true)
    }

    @Test("AgentTaskRunner safely catches and logs Ollama API outages")
    func apiOutageHandling() async throws {
        let (context, _) = try createInMemoryContext()
        let request = createTestRequest()
        let registry = ToolRegistry()

        struct ErrorMockClient: OllamaClientProtocol {
            func chat(messages: [OllamaClient.Message], tools: [OllamaClient.ToolDef]?) async throws -> OllamaClient.Message {
                throw URLError(.badServerResponse)
            }
        }

        let errorClient = ErrorMockClient()
        let runner = AgentTaskRunner(modelContext: context, client: errorClient, registry: registry)

        do {
            _ = try await runner.run(request)
            Issue.record("Expected runner.run to throw an error")
        } catch {
            // Expected to throw
        }

        let logDesc = FetchDescriptor<AgentLog>(sortBy: [SortDescriptor(\.timestamp, order: .forward)])
        let logs = try context.fetch(logDesc)

        let errorLog = logs.first(where: { $0.phase == "error" })
        #expect(errorLog != nil, "Expected an error log phase to be written to the database.")
        let content = errorLog?.content ?? ""
        #expect(content.contains("URLError") || content.contains("badServerResponse") || content.contains("Error:"))
    }

    // MARK: - Helpers

    private func createInMemoryContext() throws -> (ModelContext, ModelContainer) {
        let schema = Schema([LifeContext.self, AgentLog.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (ModelContext(container), container)
    }

    private func createTestRequest() -> AgentTaskRunner.Request {
        AgentTaskRunner.Request(
            id: UUID(),
            taskName: "Test Mission",
            systemPrompt: "You are testing.",
            triggerSchedule: "webhook",
            allowedToolIds: [],
            ownerProfileId: nil
        )
    }
}
