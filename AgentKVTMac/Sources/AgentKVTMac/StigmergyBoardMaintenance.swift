import Foundation
import ManagerCore
import SwiftData

/// Deletes expired `EphemeralPin` rows (pheromone evaporation).
enum StigmergyBoardMaintenance {
    static func evictExpiredEphemeralPins(modelContext: ModelContext) throws {
        let cutoff = Date()
        let descriptor = FetchDescriptor<EphemeralPin>(
            predicate: #Predicate<EphemeralPin> { $0.expiresAt < cutoff }
        )
        let expired = try modelContext.fetch(descriptor)
        for pin in expired {
            modelContext.delete(pin)
        }
        if !expired.isEmpty {
            try modelContext.save()
        }
    }

    /// `true` when there is board work for `workunit_board` missions.
    static func hasActiveWorkUnits(modelContext: ModelContext) throws -> Bool {
        let pending = WorkUnitState.pending.rawValue
        let inProgress = WorkUnitState.inProgress.rawValue
        let descriptor = FetchDescriptor<WorkUnit>(
            predicate: #Predicate<WorkUnit> { $0.state == pending || $0.state == inProgress }
        )
        let rows = try modelContext.fetch(descriptor)
        return !rows.isEmpty
    }
}
