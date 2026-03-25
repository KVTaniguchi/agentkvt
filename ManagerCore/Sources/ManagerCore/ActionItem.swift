import Foundation
import SwiftData

/// Dynamic button data for the iOS dashboard.
/// The Mac agent writes these; the iOS app renders them as AppIntentButtons.
@Model
public final class ActionItem {
    public var id: UUID
    public var title: String
    public var systemIntent: String
    public var payloadData: Data?
    public var relevanceScore: Double
    public var timestamp: Date
    public var missionId: UUID?
    public var isHandled: Bool
    /// When created from a user-facing flow with attribution; Mac agent rows typically leave nil.
    public var createdByProfileId: UUID?

    public init(
        id: UUID = UUID(),
        title: String,
        systemIntent: String,
        payloadData: Data? = nil,
        relevanceScore: Double = 1.0,
        timestamp: Date = Date(),
        missionId: UUID? = nil,
        isHandled: Bool = false,
        createdByProfileId: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.systemIntent = systemIntent
        self.payloadData = payloadData
        self.relevanceScore = relevanceScore
        self.timestamp = timestamp
        self.missionId = missionId
        self.isHandled = isHandled
        self.createdByProfileId = createdByProfileId
    }
}
