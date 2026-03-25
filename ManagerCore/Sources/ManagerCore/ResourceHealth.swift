import Foundation
import SwiftData

/// Durable negative trail for APIs or resources: other missions read this and backoff (slime-mold routing).
@Model
public final class ResourceHealth {
    public var id: UUID
    /// Stable key, e.g. URL host + path or tool name.
    public var resourceKey: String
    public var lastFailureAt: Date?
    public var cooldownUntil: Date?
    public var failureCount: Int
    public var lastErrorMessage: String?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        resourceKey: String,
        lastFailureAt: Date? = nil,
        cooldownUntil: Date? = nil,
        failureCount: Int = 0,
        lastErrorMessage: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.resourceKey = resourceKey
        self.lastFailureAt = lastFailureAt
        self.cooldownUntil = cooldownUntil
        self.failureCount = failureCount
        self.lastErrorMessage = lastErrorMessage
        self.updatedAt = updatedAt
    }
}
