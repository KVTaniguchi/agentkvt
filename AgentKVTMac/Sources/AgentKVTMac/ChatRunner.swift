import Foundation
import ManagerCore
import SwiftData

/// Processes pending chat work from either the legacy local store or the backend queue.
public final class ChatRunner: @unchecked Sendable {
    private enum Storage {
        case local(ModelContext)
        case backend(BackendAPIClient)
    }

    private let storage: Storage
    private let client: any OllamaClientProtocol
    private let registry: ToolRegistry

    public init(modelContext: ModelContext, client: any OllamaClientProtocol, registry: ToolRegistry) {
        self.storage = .local(modelContext)
        self.client = client
        self.registry = registry
    }

    public init(backendClient: BackendAPIClient, client: any OllamaClientProtocol, registry: ToolRegistry) {
        self.storage = .backend(backendClient)
        self.client = client
        self.registry = registry
    }

    /// Process the next pending user message, if any. Returns true when work was done.
    @discardableResult
    public func processNextPendingMessage() async throws -> Bool {
        switch storage {
        case .local(let modelContext):
            return try await processNextPendingLocalMessage(modelContext: modelContext)
        case .backend(let backendClient):
            return try await processNextPendingBackendMessage(backendClient: backendClient)
        }
    }

    private func processNextPendingLocalMessage(modelContext: ModelContext) async throws -> Bool {
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
            let result = try await TokenUsageLogger.$currentTask.withValue("chat") {
                try await loop.run(messages: messages) { [modelContext] event in
                    guard let log = ChatRunner.makeLog(for: event) else { return }
                    modelContext.insert(log)
                    try? modelContext.save()
                }
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
                    phase: "error",
                    content: "Chat failed: \(error)"
                )
            )
            try modelContext.save()
            return true
        }
    }

    private func processNextPendingBackendMessage(backendClient: BackendAPIClient) async throws -> Bool {
        guard let claimed = try await backendClient.claimNextPendingChatMessage() else {
            return false
        }

        do {
            let allowedToolIds = claimed.chatThread.allowedToolIds.isEmpty
                ? ChatThread.defaultAllowedToolIds
                : claimed.chatThread.allowedToolIds
            let loop = AgentLoop(client: client, registry: registry, allowedToolIds: allowedToolIds)
            let messages = buildConversation(systemPrompt: claimed.chatThread.systemPrompt, history: claimed.chatMessages)
            let metadata = [
                "chat_thread_id": claimed.chatThread.id.uuidString,
                "chat_message_id": claimed.chatMessage.id.uuidString
            ]
            let result = try await TokenUsageLogger.$currentTask.withValue("chat") {
                try await loop.run(messages: messages) { [backendClient] event in
                    guard let payload = ChatRunner.logPayload(for: event) else { return }
                    var eventMetadata = metadata
                    if let toolName = payload.toolName {
                        eventMetadata["tool_name"] = toolName
                    }
                    _ = try? await backendClient.createAgentLog(
                        phase: payload.phase,
                        content: payload.content,
                        metadata: eventMetadata
                    )
                }
            }

            _ = try await backendClient.completeChatMessage(
                id: claimed.chatMessage.id,
                assistantContent: result
            )
            _ = try? await backendClient.createAgentLog(
                phase: "chat_outcome",
                content: result,
                metadata: metadata
            )
            return true
        } catch {
            _ = try? await backendClient.failChatMessage(
                id: claimed.chatMessage.id,
                errorMessage: String(describing: error)
            )
            _ = try? await backendClient.createAgentLog(
                phase: "error",
                content: "Chat failed: \(error)",
                metadata: [
                    "chat_thread_id": claimed.chatThread.id.uuidString,
                    "chat_message_id": claimed.chatMessage.id.uuidString
                ]
            )
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

    private func buildConversation(systemPrompt: String, history: [BackendChatMessage]) -> [OllamaClient.Message] {
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

    private static func makeLog(for event: AgentLoop.Event) -> AgentLog? {
        guard let payload = logPayload(for: event) else { return nil }
        return AgentLog(
            phase: payload.phase,
            content: payload.content,
            toolName: payload.toolName
        )
    }

    private static func logPayload(for event: AgentLoop.Event) -> (phase: String, content: String, toolName: String?)? {
        switch event {
        case .assistantResponse(let content, let toolCalls):
            return (
                phase: "chat_assistant",
                content: content ?? "Assistant requested \(toolCalls.count) tool call(s).",
                toolName: nil
            )
        case .toolCallRequested(let name, let arguments):
            return (phase: "tool_call", content: arguments, toolName: name)
        case .toolCallCompleted(let name, let result, _):
            return (phase: "tool_result", content: result, toolName: name)
        case .finalResponse(let content):
            return (phase: "assistant_final", content: content, toolName: nil)
        case .maxRoundsReached:
            return (
                phase: "warning",
                content: "Chat loop reached max rounds before producing a final response.",
                toolName: nil
            )
        }
    }
}
