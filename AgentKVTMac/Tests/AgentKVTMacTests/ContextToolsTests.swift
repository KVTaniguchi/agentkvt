import Foundation
import Testing
import SwiftData
import ManagerCore
@testable import AgentKVTMac

@Suite("Context Tools Tests")
struct ContextToolsTests {
    
    // MARK: - GetLifeContextTool Tests
    
    @Test("GetLifeContextTool returns specific key when requested")
    func getSpecificLifeContext() async throws {
        let (context, _) = try createInMemoryContext()
        context.insert(LifeContext(key: "goals", value: "Ship v1"))
        context.insert(LifeContext(key: "location", value: "SF"))
        try context.save()
        
        let tool = makeGetLifeContextTool(modelContext: context)
        let result = try await tool.handler(["key": "goals"])
        
        #expect(result.contains("LifeContext [goals]: Ship v1"))
        #expect(!result.contains("location"))
    }
    
    @Test("GetLifeContextTool returns all available keys when no key matches or requested")
    func getAllLifeContext() async throws {
        let (context, _) = try createInMemoryContext()
        context.insert(LifeContext(key: "goals", value: "Ship v1"))
        context.insert(LifeContext(key: "location", value: "SF"))
        try context.save()
        
        let tool = makeGetLifeContextTool(modelContext: context)
        let result = try await tool.handler([:])
        
        #expect(result.contains("Available LifeContext keys:"))
        #expect(result.contains("goals"))
        #expect(result.contains("location"))
    }
    
    @Test("GetLifeContextTool returns not found message for missing key")
    func missingLifeContextKey() async throws {
        let (context, _) = try createInMemoryContext()
        context.insert(LifeContext(key: "goals", value: "Ship v1"))
        try context.save()
        
        let tool = makeGetLifeContextTool(modelContext: context)
        let result = try await tool.handler(["key": "missing_key"])
        
        #expect(result.contains("not found"))
    }

    @Test("FetchMissionStatusTool returns mission details and recent logs")
    func fetchMissionStatusReturnsRecentMissionActivity() async throws {
        let (context, _) = try createInMemoryContext()
        let lastRun = Date().addingTimeInterval(-300)
        let mission = MissionDefinition(
            missionName: "Job Scout",
            systemPrompt: "Look for jobs",
            triggerSchedule: "daily|08:00",
            allowedMCPTools: ["web_search_and_fetch"],
            lastRunAt: lastRun
        )
        context.insert(mission)
        context.insert(AgentLog(
            missionId: mission.id,
            missionName: mission.missionName,
            phase: "outcome",
            content: "Found 3 matching roles."
        ))
        try context.save()

        let tool = makeFetchMissionStatusTool(modelContext: context)
        let result = try await tool.handler([:])

        #expect(result.contains("Mission: Job Scout"))
        #expect(result.contains("Trigger: daily|08:00"))
        #expect(result.contains("Latest run completed successfully."))
        #expect(result.contains("Found 3 matching roles."))
    }

    @Test("FetchMissionStatusTool filters by mission name")
    func fetchMissionStatusFiltersByMissionName() async throws {
        let (context, _) = try createInMemoryContext()
        context.insert(MissionDefinition(
            missionName: "Budget Sentinel",
            systemPrompt: "Track transactions",
            triggerSchedule: "daily|20:00",
            allowedMCPTools: []
        ))
        context.insert(MissionDefinition(
            missionName: "Career Scout",
            systemPrompt: "Track jobs",
            triggerSchedule: "daily|08:00",
            allowedMCPTools: []
        ))
        try context.save()

        let tool = makeFetchMissionStatusTool(modelContext: context)
        let result = try await tool.handler(["mission_name": "career"])

        #expect(result.contains("Mission: Career Scout"))
        #expect(!result.contains("Budget Sentinel"))
    }
    
    // MARK: - DropzoneTools Tests
    
    @Test("ListDropzoneFilesTool lists available files and ignores hidden")
    func listDropzoneFiles() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        // Setup mock files
        let file1 = dir.appendingPathComponent("resume.pdf")
        let file2 = dir.appendingPathComponent("budget.csv")
        let hiddenFile = dir.appendingPathComponent(".DS_Store")
        
        try "pdf".write(to: file1, atomically: true, encoding: .utf8)
        try "csv".write(to: file2, atomically: true, encoding: .utf8)
        try "hidden".write(to: hiddenFile, atomically: true, encoding: .utf8)
        
        let tool = makeListDropzoneFilesTool(directory: dir)
        let result = try await tool.handler([:])
        
        #expect(result.contains("Available files"))
        #expect(result.contains("resume.pdf"))
        #expect(result.contains("budget.csv"))
        #expect(!result.contains(".DS_Store"))
    }
    
    @Test("ListDropzoneFilesTool handles empty directory")
    func listEmptyDropzone() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let tool = makeListDropzoneFilesTool(directory: dir)
        let result = try await tool.handler([:])
        
        #expect(result.contains("The dropzone is currently empty."))
    }
    
    @Test("ReadDropzoneFileTool reads valid text file")
    func readValidDropzoneFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let file = dir.appendingPathComponent("notes.txt")
        try "Hello World".write(to: file, atomically: true, encoding: .utf8)
        
        let tool = makeReadDropzoneFileTool(directory: dir)
        let result = try await tool.handler(["filename": "notes.txt"])
        
        #expect(result == "Hello World")
    }
    
    @Test("ReadDropzoneFileTool handles missing file gracefully")
    func readMissingDropzoneFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let tool = makeReadDropzoneFileTool(directory: dir)
        let result = try await tool.handler(["filename": "nonexistent.txt"])
        
        #expect(result.contains("Error: File 'nonexistent.txt' not found."))
    }
    
    @Test("ReadDropzoneFileTool prevents path traversal")
    func readPathTraversalDropzoneFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        // This tool only joins the lastPathComponent, so ../../etc/passwd becomes passwd
        let tool = makeReadDropzoneFileTool(directory: dir)
        let result = try await tool.handler(["filename": "../../etc/passwd"])
        
        #expect(result.contains("Error: File 'passwd' not found."))
    }
    
    // MARK: - Helpers
    
    private func createInMemoryContext() throws -> (ModelContext, ModelContainer) {
        let schema = Schema([LifeContext.self, MissionDefinition.self, ActionItem.self, AgentLog.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (ModelContext(container), container)
    }
}
