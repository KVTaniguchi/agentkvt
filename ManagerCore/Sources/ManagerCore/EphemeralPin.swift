import Foundation
import SwiftData

/// Short-lived “pheromone” pin that evaporates after `expiresAt` (clock-tick GC on the Mac runner).
@Model
public final class EphemeralPin {
    public var id: UUID
    public var content: String
    public var category: String?
    public var strength: Double
    public var expiresAt: Date
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        content: String,
        category: String? = nil,
        strength: Double = 1.0,
        expiresAt: Date,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.category = category
        self.strength = strength
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }
}
