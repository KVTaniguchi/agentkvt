import Foundation
import SwiftData

/// Configuration for a user-defined background task (mission).
/// Users construct missions from the iOS interface; the Mac agent runs them on schedule.
@Model
public final class MissionDefinition {
    public var id: UUID
    public var missionName: String
    public var systemPrompt: String
    public var triggerSchedule: String // Encoded: "daily|08:00", "weekly|monday", "webhook", etc.
    public var allowedMCPTools: [String] // Tool IDs this mission is authorized to use
    /// Optional per-person owner attribution for family-profile aware mission execution.
    public var ownerProfileId: UUID?
    public var isEnabled: Bool
    public var lastRunAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        missionName: String,
        systemPrompt: String,
        triggerSchedule: String,
        allowedMCPTools: [String],
        ownerProfileId: UUID? = nil,
        isEnabled: Bool = true,
        lastRunAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.missionName = missionName
        self.systemPrompt = systemPrompt
        self.triggerSchedule = triggerSchedule
        self.allowedMCPTools = allowedMCPTools
        self.ownerProfileId = ownerProfileId
        self.isEnabled = isEnabled
        self.lastRunAt = lastRunAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
