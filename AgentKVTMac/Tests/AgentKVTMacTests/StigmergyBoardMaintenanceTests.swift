import Foundation
import SwiftData
import Testing
@testable import AgentKVTMac
@testable import ManagerCore

struct StigmergyBoardMaintenanceTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            LifeContext.self,
            ResearchSnapshot.self,
            AgentLog.self,
            InboundFile.self,
            ChatThread.self,
            ChatMessage.self,

            WorkUnit.self,
            EphemeralPin.self,
            ResourceHealth.self,
            FamilyMember.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test("Eviction removes EphemeralPin rows past expiresAt")
    func evictsExpiredPins() throws {
        let context = try makeContext()
        let past = Date().addingTimeInterval(-300)
        let future = Date().addingTimeInterval(300)
        context.insert(EphemeralPin(content: "stale", expiresAt: past))
        context.insert(EphemeralPin(content: "fresh", expiresAt: future))
        try context.save()

        try StigmergyBoardMaintenance.evictExpiredEphemeralPins(modelContext: context)

        let remaining = try context.fetch(FetchDescriptor<EphemeralPin>())
        #expect(remaining.count == 1)
        #expect(remaining[0].content == "fresh")
    }

    @Test("hasActiveWorkUnits is true only for pending or in_progress")
    func activeWorkUnitDetection() throws {
        let context = try makeContext()
        let pending = WorkUnit(title: "A", state: WorkUnitState.pending.rawValue)
        let done = WorkUnit(title: "B", state: WorkUnitState.done.rawValue)
        context.insert(pending)
        context.insert(done)
        try context.save()

        #expect(try StigmergyBoardMaintenance.hasActiveWorkUnits(modelContext: context) == true)

        pending.state = WorkUnitState.done.rawValue
        try context.save()
        #expect(try StigmergyBoardMaintenance.hasActiveWorkUnits(modelContext: context) == false)
    }
}
