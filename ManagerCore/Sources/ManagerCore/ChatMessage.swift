import Foundation
import SwiftData

/// One message in an optional chat thread shared between iPhone and the Mac runner.
@Model
public final class ChatMessage {
    public var id: UUID
    public var threadId: UUID
    public var role: String
    public var content: String
    public var status: String
    public var errorMessage: String?
    public var timestamp: Date
    /// Set for `role == user` when sent from iOS; assistant/system messages omit.
    public var authorProfileId: UUID?

    public init(
        id: UUID = UUID(),
        threadId: UUID,
        role: String,
        content: String,
        status: String = ChatMessageStatus.completed.rawValue,
        errorMessage: String? = nil,
        timestamp: Date = Date(),
        authorProfileId: UUID? = nil
    ) {
        self.id = id
        self.threadId = threadId
        self.role = role
        self.content = content
        self.status = status
        self.errorMessage = errorMessage
        self.timestamp = timestamp
        self.authorProfileId = authorProfileId
    }
}

public enum ChatMessageStatus: String, Sendable {
    case pending
    case processing
    case completed
    case failed
}
