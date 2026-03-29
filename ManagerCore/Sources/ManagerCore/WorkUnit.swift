import Foundation
import SwiftData

/// Lifecycle for a multi-step family job (sematectonic “mound”): the **shape** of this record
/// (state + payload) triggers which mission or tool runs next.
public enum WorkUnitState: String, Sendable, Codable, CaseIterable {
    case draft
    case pending
    case inProgress = "in_progress"
    case blocked
    case done
}

/// A durable work item on the shared board: JSON mound payload + explicit state for stigmergic coordination.
@Model
public final class WorkUnit {
    public var id: UUID = UUID()
    public var title: String = ""
    /// Free-form category for mission filtering (e.g. "travel", "school").
    public var category: String = "general"
    /// Optional objective that owns this work unit when the board is being used for Objectives.
    public var objectiveId: UUID?
    /// Optional Rails task that seeded this work unit.
    public var sourceTaskId: UUID?
    /// Objective-specific subtype such as objective_root, objective_research, or objective_synthesis.
    public var workType: String = "general"
    public var state: String = WorkUnitState.draft.rawValue
    /// Evolving JSON blob (flight_info, hotel_info, etc.).
    public var moundPayload: Data?
    /// Optional hint so missions can fetch without parsing JSON every time.
    public var activePhaseHint: String?
    /// Pheromone-style priority for ordering when multiple units are ready.
    public var priority: Double = 1.0
    public var claimedByMissionId: UUID?
    public var claimedUntil: Date?
    /// Human-readable worker label currently responsible for this work unit, when claimed.
    public var workerLabel: String?
    /// Heartbeat written by the active worker so the UI can show that the board is still moving.
    public var lastHeartbeatAt: Date?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    /// Optional: family member who created this unit (e.g. from a future iOS flow).
    public var createdByProfileId: UUID?

    public init(
        id: UUID = UUID(),
        title: String,
        category: String = "general",
        objectiveId: UUID? = nil,
        sourceTaskId: UUID? = nil,
        workType: String = "general",
        state: String = WorkUnitState.draft.rawValue,
        moundPayload: Data? = nil,
        activePhaseHint: String? = nil,
        priority: Double = 1.0,
        claimedByMissionId: UUID? = nil,
        claimedUntil: Date? = nil,
        workerLabel: String? = nil,
        lastHeartbeatAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        createdByProfileId: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.objectiveId = objectiveId
        self.sourceTaskId = sourceTaskId
        self.workType = workType
        self.state = state
        self.moundPayload = moundPayload
        self.activePhaseHint = activePhaseHint
        self.priority = priority
        self.claimedByMissionId = claimedByMissionId
        self.claimedUntil = claimedUntil
        self.workerLabel = workerLabel
        self.lastHeartbeatAt = lastHeartbeatAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdByProfileId = createdByProfileId
    }
}

public extension WorkUnit {
    /// Set `MissionDefinition.triggerSchedule` to this value for missions that run on the clock tick when
    /// at least one `WorkUnit` is `pending` or `in_progress` (stigmergic board polling).
    static let boardMissionTriggerSchedule = "workunit_board"
}
