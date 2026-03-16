import Foundation
import SwiftData

/// File uploaded from iOS for the Mac agent to consume.
@Model
public final class InboundFile {
    public var id: UUID
    public var fileName: String
    public var fileData: Data
    public var timestamp: Date
    public var isProcessed: Bool

    public init(
        id: UUID = UUID(),
        fileName: String,
        fileData: Data,
        timestamp: Date = Date(),
        isProcessed: Bool = false
    ) {
        self.id = id
        self.fileName = fileName
        self.fileData = fileData
        self.timestamp = timestamp
        self.isProcessed = isProcessed
    }
}

