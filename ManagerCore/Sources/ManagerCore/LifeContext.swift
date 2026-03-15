import Foundation
import SwiftData

/// Static facts and user preferences the agent must consult before taking action
/// (e.g., specific goals, geographic locations, important dates).
@Model
public final class LifeContext {
    public var id: UUID
    public var key: String
    public var value: String
    public var updatedAt: Date

    public init(id: UUID = UUID(), key: String, value: String, updatedAt: Date = Date()) {
        self.id = id
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}
