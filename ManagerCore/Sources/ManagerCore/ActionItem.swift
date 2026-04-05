import Foundation
import SwiftData

/// Dynamic button data for the iOS dashboard.
/// The Mac agent writes these; the iOS app renders them as AppIntentButtons.
@Model
public final class ActionItem {
    public var id: UUID = UUID()
    public var title: String = ""
    public var systemIntent: String = ""
    public var payloadData: Data?
    public var relevanceScore: Double = 1.0
    public var timestamp: Date = Date()
    public var isHandled: Bool = false
    /// When created from a user-facing flow with attribution; Mac agent rows typically leave nil.
    public var createdByProfileId: UUID?

    public init(
        id: UUID = UUID(),
        title: String,
        systemIntent: String,
        payloadData: Data? = nil,
        relevanceScore: Double = 1.0,
        timestamp: Date = Date(),
        isHandled: Bool = false,
        createdByProfileId: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.systemIntent = systemIntent
        self.payloadData = payloadData
        self.relevanceScore = relevanceScore
        self.timestamp = timestamp
        self.isHandled = isHandled
        self.createdByProfileId = createdByProfileId
    }
}
