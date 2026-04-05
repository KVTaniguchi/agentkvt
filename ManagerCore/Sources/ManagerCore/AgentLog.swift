import Foundation
import SwiftData

/// Append-only ledger of what the agent "thought," what tools it executed, and the outcome.
/// Enables the user to audit the agent's behavior.
@Model
public final class AgentLog {
    public var id: UUID = UUID()
    public var phase: String = "" // e.g. "reasoning", "tool_call", "outcome"
    public var content: String = ""
    public var toolName: String?
    public var timestamp: Date = Date()

    public init(
        id: UUID = UUID(),
        phase: String,
        content: String,
        toolName: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.phase = phase
        self.content = content
        self.toolName = toolName
        self.timestamp = timestamp
    }
}
