import Foundation
import ManagerCore
import SwiftData

/// Processes optional chat threads written by iPhone into the shared store.
public final class ChatRunner: @unchecked Sendable {
    private let modelContext: ModelContext
    private let client: any OllamaClientProtocol
    private let registry: ToolRegistry

    public init(modelContext: ModelContext, client: any OllamaClientProtocol, registry: ToolRegistry) {
        self.modelContext = modelContext
        self.client = client
        self.registry = registry
    }

    /// Process the next pending user message, if any. Returns true when work was done.
    @discardableResult
    public func processNextPendingMessage() async throws -> Bool {
        let pendingStatus = ChatMessageStatus.pending.rawValue
        let pendingDescriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> {
                $0.role == "user" && $0.status == pendingStatus
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        guard let pending = try modelContext.fetch(pendingDescriptor).first else {
            return false
        }

        let threadID = pending.threadId
        let threadDescriptor = FetchDescriptor<ChatThread>(
            predicate: #Predicate<ChatThread> { $0.id == threadID }
        )
        guard let thread = try modelContext.fetch(threadDescriptor).first else {
            pending.status = ChatMessageStatus.failed.rawValue
            pending.errorMessage = "Thread not found."
            try modelContext.save()
            return true
        }

        pending.status = ChatMessageStatus.processing.rawValue
        pending.errorMessage = nil
        thread.updatedAt = Date()
        try modelContext.save()

        do {
            let historyDescriptor = FetchDescriptor<ChatMessage>(
                predicate: #Predicate<ChatMessage> { $0.threadId == threadID },
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )
            let history = try modelContext.fetch(historyDescriptor)
            let allowedToolIds = thread.allowedToolIds.isEmpty ? ChatThread.defaultAllowedToolIds : thread.allowedToolIds
            let loop = AgentLoop(client: client, registry: registry, allowedToolIds: allowedToolIds)
            let messages = buildConversation(systemPrompt: thread.systemPrompt, history: history)
            let result = try await loop.run(messages: messages) { [modelContext] event in
                guard let log = ChatRunner.makeLog(for: event, thread: thread) else { return }
                modelContext.insert(log)
                try? modelContext.save()
            }

            pending.status = ChatMessageStatus.completed.rawValue
            pending.errorMessage = nil
            let assistantMessage = ChatMessage(
                threadId: thread.id,
                role: "assistant",
                content: result,
                status: ChatMessageStatus.completed.rawValue
            )
            modelContext.insert(assistantMessage)
            modelContext.insert(
                AgentLog(
                    missionName: "Chat: \(thread.title)",
                    phase: "chat_outcome",
                    content: result
                )
            )
            thread.updatedAt = Date()
            try modelContext.save()
            return true
        } catch {
            pending.status = ChatMessageStatus.failed.rawValue
            pending.errorMessage = String(describing: error)
            thread.updatedAt = Date()
            modelContext.insert(
                AgentLog(
                    missionName: "Chat: \(thread.title)",
                    phase: "error",
                    content: "Chat failed: \(error)"
                )
            )
            try modelContext.save()
            return true
        }
    }

    private func buildConversation(systemPrompt: String, history: [ChatMessage]) -> [OllamaClient.Message] {
        let transcript = history
            .filter { $0.status != ChatMessageStatus.failed.rawValue }
            .map { message in
                OllamaClient.Message(
                    role: message.role,
                    content: message.content,
                    toolCalls: nil
                )
            }
        return [.init(role: "system", content: systemPrompt, toolCalls: nil)] + transcript
    }

    private static func makeLog(for event: AgentLoop.Event, thread: ChatThread) -> AgentLog? {
        switch event {
        case .assistantResponse(let content, let toolCalls):
            return AgentLog(
                missionName: "Chat: \(thread.title)",
                phase: "chat_assistant",
                content: content ?? "Assistant requested \(toolCalls.count) tool call(s)."
            )
        case .toolCallRequested(let name, let arguments):
            return AgentLog(
                missionName: "Chat: \(thread.title)",
                phase: "tool_call",
                content: arguments,
                toolName: name
            )
        case .toolCallCompleted(let name, let result, _):
            return AgentLog(
                missionName: "Chat: \(thread.title)",
                phase: "tool_result",
                content: result,
                toolName: name
            )
        case .finalResponse(let content):
            return AgentLog(
                missionName: "Chat: \(thread.title)",
                phase: "assistant_final",
                content: content
            )
        case .maxRoundsReached:
            return AgentLog(
                missionName: "Chat: \(thread.title)",
                phase: "warning",
                content: "Chat loop reached max rounds before producing a final response."
            )
        }
    }
}
