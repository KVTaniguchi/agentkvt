import Foundation
import SwiftData

/// Privilege tier for the agent that wrote an EphemeralPin.
/// Supervisors only consume pins written by lower tiers, preventing a compromised
/// research worker from injecting supervisor-level directives via the blackboard.
public enum EphemeralPinRole: String, Codable, Sendable {
    case research    // lowest — web scrapers, data gatherers
    case synthesis   // mid — aggregators, summarizers
    case supervisor  // highest — planners, work-unit spawners
}

/// Short-lived “pheromone” pin that evaporates after `expiresAt` (clock-tick GC on the Mac runner).
@Model
public final class EphemeralPin {
    public var id: UUID = UUID()
    public var content: String = ""
    public var category: String?
    public var strength: Double = 1.0
    public var expiresAt: Date = Date()
    public var createdAt: Date = Date()
    /// Role of the agent that wrote this pin. Supervisors must only consume pins from .research or .synthesis.
    public var originRole: String = EphemeralPinRole.research.rawValue

    public init(
        id: UUID = UUID(),
        content: String,
        category: String? = nil,
        strength: Double = 1.0,
        expiresAt: Date,
        createdAt: Date = Date(),
        originRole: EphemeralPinRole = .research
    ) {
        self.id = id
        self.content = content
        self.category = category
        self.strength = strength
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.originRole = originRole.rawValue
    }
}
