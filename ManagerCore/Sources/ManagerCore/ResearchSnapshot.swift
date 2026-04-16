import Foundation
import SwiftData

/// Persistent key/value snapshot for research missions. Stores the last observed value
/// for a tracked metric (e.g. a hotel rate or flight price) and records whether a
/// meaningful change was detected on the most recent write.
@Model
public final class ResearchSnapshot {
    public var id: UUID = UUID()
    public var key: String = ""
    public var lastKnownValue: String = ""
    public var checkedAt: Date = Date()
    public var deltaNote: String? = nil
    public var isRepellent: Bool = false
    public var repellentReason: String? = nil
    public var repellentScope: String? = nil
    public var snapshotKind: String = "result"

    public init(
        id: UUID = UUID(),
        key: String,
        lastKnownValue: String,
        checkedAt: Date = Date(),
        deltaNote: String? = nil,
        isRepellent: Bool = false,
        repellentReason: String? = nil,
        repellentScope: String? = nil,
        snapshotKind: String = "result"
    ) {
        self.id = id
        self.key = key
        self.lastKnownValue = lastKnownValue
        self.checkedAt = checkedAt
        self.deltaNote = deltaNote
        self.isRepellent = isRepellent
        self.repellentReason = repellentReason
        self.repellentScope = repellentScope
        self.snapshotKind = snapshotKind
    }
}
