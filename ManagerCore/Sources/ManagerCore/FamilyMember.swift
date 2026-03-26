import Foundation
import SwiftData

/// In-app identity for a person in the household. Devices use the shared family Apple ID for iCloud;
/// this record attributes actions and messages to an individual.
@Model
public final class FamilyMember {
    public var id: UUID = UUID()
    public var displayName: String = ""
    /// Optional short label for lists (e.g. emoji).
    public var symbol: String = ""
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        displayName: String,
        symbol: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.symbol = symbol
        self.createdAt = createdAt
    }
}
