import Foundation
import SwiftData
import Testing
@testable import AgentKVTMac
@testable import ManagerCore

struct CloudInboundServiceTests {

    private func makeTestContainer() throws -> ModelContext {
        let schema = Schema([
            LifeContext.self,
            MissionDefinition.self,
            ActionItem.self,
            AgentLog.self,
            InboundFile.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test("CloudInboundService writes unprocessed InboundFile to directory and marks processed")
    func syncWritesFilesAndMarksProcessed() throws {
        let context = try makeTestContainer()
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "agentkvt-inbound-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let data = "hello inbound".data(using: .utf8)!
        let file = InboundFile(fileName: "inbound.txt", fileData: data)
        context.insert(file)
        try context.save()

        let service = CloudInboundService(modelContext: context, directory: tempDir)
        service.syncInboundFiles()

        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        #expect(contents.contains { $0.lastPathComponent == "inbound.txt" })

        let fetch = FetchDescriptor<InboundFile>()
        let files = try context.fetch(fetch)
        #expect(files.count == 1)
        #expect(files[0].isProcessed == true)
    }
}

