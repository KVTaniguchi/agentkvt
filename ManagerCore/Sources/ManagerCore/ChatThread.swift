import Foundation
import SwiftData

/// Optional conversational thread that can be used from iPhone without replacing the main ActionItem UI.
@Model
public final class ChatThread {
    public var id: UUID = UUID()
    public var title: String = "Assistant"
    public var systemPrompt: String = ChatThread.defaultSystemPrompt
    public var allowedToolIds: [String] = []
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    /// Family member who created this thread (iOS); optional for legacy/sync.
    public var createdByProfileId: UUID?

    public init(
        id: UUID = UUID(),
        title: String = "Assistant",
        systemPrompt: String = ChatThread.defaultSystemPrompt,
        allowedToolIds: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        createdByProfileId: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.systemPrompt = systemPrompt
        self.allowedToolIds = allowedToolIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdByProfileId = createdByProfileId
    }
}

public extension ChatThread {
    static let defaultSystemPrompt = """
    You are AgentKVT's optional chat assistant. Be concise, helpful, and privacy-conscious. \
    When a user asks you to create a concrete follow-up they can act on later, prefer using the \
    write_action_item tool if it is available in this chat.
    """
}
