import ManagerCore
import SwiftData

// MissionDefinition instances stay on the runner's deliberately serialized execution path.
// This narrow shim preserves existing actor handoff behavior under Swift 6 checking.
extension ModelContext: @retroactive @unchecked Sendable {}
extension MissionDefinition: @retroactive @unchecked Sendable {}
