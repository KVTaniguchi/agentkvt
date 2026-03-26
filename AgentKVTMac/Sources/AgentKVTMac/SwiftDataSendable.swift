import ManagerCore
import SwiftData

// SwiftData's ModelContext is used on a deliberately serialized execution path here.
// We bridge it into Swift 6's sendability checks so the queue actor can own it.
extension ModelContext: @retroactive @unchecked Sendable {}
extension MissionDefinition: @retroactive @unchecked Sendable {}
