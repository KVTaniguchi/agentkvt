import Foundation
import SwiftData

/// File uploaded from iOS for the Mac agent to consume.
@Model
public final class InboundFile {
    public var id: UUID = UUID()
    public var fileName: String = ""
    public var fileData: Data = Data()
    public var timestamp: Date = Date()
    public var isProcessed: Bool = false
    public var uploadedByProfileId: UUID?

    public init(
        id: UUID = UUID(),
        fileName: String,
        fileData: Data,
        timestamp: Date = Date(),
        isProcessed: Bool = false,
        uploadedByProfileId: UUID? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.fileData = fileData
        self.timestamp = timestamp
        self.isProcessed = isProcessed
        self.uploadedByProfileId = uploadedByProfileId
    }
}
