import Foundation

public enum BackendAPIError: Error, LocalizedError {
    case invalidBaseURL(String)
    case requestFailed(statusCode: Int, body: String)
    case invalidPayload(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let path):
            return "Invalid backend URL path: \(path)"
        case .requestFailed(let statusCode, let body):
            return "Backend request failed with HTTP \(statusCode): \(body)"
        case .invalidPayload(let message):
            return "Invalid backend payload: \(message)"
        }
    }
}

public struct BackendChatThread: Codable, Sendable {
    public let id: UUID
    public let workspaceId: UUID
    public let createdByProfileId: UUID?
    public let title: String
    public let systemPrompt: String
    public let allowedToolIds: [String]
    public let latestMessagePreview: String?
    public let latestMessageRole: String?
    public let latestMessageStatus: String?
    public let latestMessageAt: Date?
    public let pendingMessageCount: Int
    public let messageCount: Int
    public let createdAt: Date
    public let updatedAt: Date
}

public struct BackendChatMessage: Codable, Sendable {
    public let id: UUID
    public let chatThreadId: UUID
    public let role: String
    public let content: String
    public let status: String
    public let errorMessage: String?
    public let timestamp: Date
    public let authorProfileId: UUID?
    public let createdAt: Date
    public let updatedAt: Date
}

public struct BackendClaimedChatMessage: Sendable {
    public let chatThread: BackendChatThread
    public let chatMessage: BackendChatMessage
    public let chatMessages: [BackendChatMessage]
}

public struct BackendCompletedChatMessage: Sendable {
    public let chatMessage: BackendChatMessage
    public let assistantMessage: BackendChatMessage
}

public struct BackendInboundFile: Codable, Sendable {
    public let id: UUID
    public let workspaceId: UUID
    public let uploadedByProfileId: UUID?
    public let fileName: String
    public let contentType: String?
    public let byteSize: Int
    public let isProcessed: Bool
    public let processedAt: Date?
    public let timestamp: Date
    public let createdAt: Date
    public let updatedAt: Date
    public let fileBase64: String?
}



public struct BackendActionItem: Codable, Sendable {
    public let id: UUID
    public let workspaceId: UUID

    public let ownerProfileId: UUID?
    public let title: String
    public let systemIntent: String
    public let payloadJson: [String: String]
    public let relevanceScore: Double
    public let isHandled: Bool
    public let handledAt: Date?
    public let timestamp: Date
    public let createdBy: String
    public let createdAt: Date
    public let updatedAt: Date
}

public struct BackendAgentLog: Codable, Sendable {
    public let id: UUID
    public let workspaceId: UUID

    public let phase: String
    public let content: String
    public let metadataJson: [String: String]
    public let timestamp: Date
    public let createdAt: Date
    public let updatedAt: Date
}

private struct BackendClaimedChatMessageEnvelope: Codable {
    let pending: Bool
    let chatThread: BackendChatThread?
    let chatMessage: BackendChatMessage?
    let chatMessages: [BackendChatMessage]?
}

private struct BackendCompletedChatMessageEnvelope: Codable {
    let chatMessage: BackendChatMessage
    let assistantMessage: BackendChatMessage
}

private struct BackendChatMessageEnvelope: Codable {
    let chatMessage: BackendChatMessage
}

private struct BackendInboundFileEnvelope: Codable {
    let inboundFile: BackendInboundFile
}

private struct BackendInboundFilesEnvelope: Codable {
    let inboundFiles: [BackendInboundFile]
}



private struct BackendActionItemEnvelope: Codable {
    let actionItem: BackendActionItem
}

private struct BackendActionItemsEnvelope: Codable {
    let actionItems: [BackendActionItem]
}

private struct BackendAgentLogEnvelope: Codable {
    let agentLog: BackendAgentLog
}

private struct BackendAgentLogsEnvelope: Codable {
    let agentLogs: [BackendAgentLog]
}

public struct BackendResearchSnapshot: Codable, Sendable {
    public let id: UUID
    public let objectiveId: UUID
    public let taskId: UUID?
    public let key: String
    public let value: String
    public let previousValue: String?
    public let deltaNote: String?
    public let checkedAt: Date
    public let createdAt: Date
    public let updatedAt: Date
}

/// One objective row from `GET /v1/objectives/:id` (used to hydrate `goal` when local payloads omit it).
public struct BackendObjective: Codable, Sendable {
    public let id: UUID
    public let workspaceId: UUID
    public let goal: String
    public let status: String
    public let priority: Int
    public let createdAt: Date
    public let updatedAt: Date
}

private struct BackendResearchSnapshotEnvelope: Codable {
    let researchSnapshot: BackendResearchSnapshot
}

private struct BackendResearchSnapshotsListEnvelope: Codable {
    let researchSnapshots: [BackendResearchSnapshot]
}

private struct BackendObjectiveEnvelope: Codable {
    let objective: BackendObjective
}

public actor BackendAPIClient {
    public let baseURL: URL
    public let workspaceSlug: String
    public let agentToken: String?

    private let session: URLSession
    private let decoder: JSONDecoder
    private let isoFormatter: ISO8601DateFormatter

    private static func normalizeAPIBaseURL(_ url: URL) -> URL {
        var string = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        while string.hasSuffix("/") { string.removeLast() }
        if string.lowercased().hasSuffix("/v1") {
            string = String(string.dropLast("/v1".count))
            while string.hasSuffix("/") { string.removeLast() }
        }
        return URL(string: string) ?? url
    }

    public init(
        baseURL: URL,
        workspaceSlug: String,
        agentToken: String? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = Self.normalizeAPIBaseURL(baseURL)
        self.workspaceSlug = workspaceSlug
        self.agentToken = agentToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .iso8601
        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.formatOptions = [.withInternetDateTime]
    }

    /// Loads the objective (including `goal`) from the API. Uses workspace slug only — same auth as other `v1/` reads.
    public func fetchObjective(id: UUID) async throws -> BackendObjective {
        let data = try await performRequest(path: "v1/objectives/\(id.uuidString)")
        return try decoder.decode(BackendObjectiveEnvelope.self, from: data).objective
    }

    /// Fetch recent agent logs from the workspace-wide log endpoint.
    public func fetchAgentLogs(limit: Int = 100) async throws -> [BackendAgentLog] {
        let data = try await performRequest(
            path: "v1/agent_logs",
            queryItems: [URLQueryItem(name: "limit", value: "\(min(limit, 500))")]
        )
        return try decoder.decode(BackendAgentLogsEnvelope.self, from: data).agentLogs
    }

    public func createAgentLog(
        taskName: String? = nil,
        phase: String,
        content: String,
        metadata: [String: String] = [:]
    ) async throws -> BackendAgentLog {
        var mergedMetadata = metadata
        if let taskName, !taskName.isEmpty {
            mergedMetadata["task_name"] = taskName
        }

        let data = try await performRequest(
            path: "v1/agent/logs",
            method: "POST",
            jsonBody: [
                "agent_log": [
                    "phase": phase,
                    "content": content,
                    "metadata_json": mergedMetadata
                ]
            ],
            requiresAgentAuth: true
        )
        return try decoder.decode(BackendAgentLogEnvelope.self, from: data).agentLog
    }

    /// List research snapshots for an objective (optional `taskId` matches server filter).
    public func fetchResearchSnapshots(objectiveId: UUID, taskId: UUID? = nil) async throws -> [BackendResearchSnapshot] {
        var queryItems: [URLQueryItem] = []
        if let taskId {
            queryItems.append(URLQueryItem(name: "task_id", value: taskId.uuidString))
        }
        let data = try await performRequest(
            path: "v1/agent/objectives/\(objectiveId.uuidString)/research_snapshots",
            queryItems: queryItems,
            requiresAgentAuth: true
        )
        return try decoder.decode(BackendResearchSnapshotsListEnvelope.self, from: data).researchSnapshots
    }

    /// Write (upsert) a research snapshot for an objective. The server tracks the
    /// previous value and sets `delta_note` automatically when the value changes.
    /// Pass `taskId` to simultaneously mark the parent task as completed.
    public func writeResearchSnapshot(
        objectiveId: UUID,
        taskId: UUID? = nil,
        key: String,
        value: String,
        markTaskCompleted: Bool? = nil
    ) async throws -> BackendResearchSnapshot {
        if let msg = ObjectiveResearchSnapshotPayload.clientRejectionMessageIfInvalid(value) {
            throw BackendAPIError.invalidPayload(msg)
        }
        let path = "v1/agent/objectives/\(objectiveId.uuidString)/research_snapshots"
        var queryItems: [URLQueryItem] = []
        if let taskId {
            queryItems.append(URLQueryItem(name: "task_id", value: taskId.uuidString))
        }
        if let markTaskCompleted {
            queryItems.append(URLQueryItem(name: "mark_task_completed", value: markTaskCompleted ? "true" : "false"))
        }
        let data = try await performRequest(
            path: path,
            method: "POST",
            queryItems: queryItems,
            jsonBody: ["research_snapshot": ["key": key, "value": value]],
            requiresAgentAuth: true
        )
        return try decoder.decode(BackendResearchSnapshotEnvelope.self, from: data).researchSnapshot
    }

    /// Registers this agent's capabilities and webhook URL with the backend.
    /// Call on startup and every ~15s as a heartbeat so TaskExecutorJob can route tasks here.
    public func registerAgent(
        agentId: String,
        capabilities: [String],
        webhookURL: String?
    ) async throws {
        var body: [String: Any] = [
            "agent_registration": [
                "agent_id": agentId,
                "capabilities": capabilities
            ] as [String: Any]
        ]
        if let webhookURL {
            var reg = (body["agent_registration"] as! [String: Any])
            reg["webhook_url"] = webhookURL
            body["agent_registration"] = reg
        }
        _ = try await performRequest(
            path: "v1/agent/register",
            method: "POST",
            jsonBody: body,
            requiresAgentAuth: true
        )
    }

    /// Long-poll variant: blocks on the server for up to 30s waiting for a Postgres NOTIFY
    /// on the `agentkvt_chat_wake` channel, then atomically reads and clears the flag.
    /// Returns `true` when a wake was pending. Replaces the 15s sleep + short poll loop.
    public func consumeChatWakeBlocking() async throws -> Bool {
        // Server blocks up to 30s; add a 5s client-side buffer to avoid racing the timeout.
        var request = URLRequest(
            url: try url(for: "v1/agent/chat_wake", queryItems: []),
            timeoutInterval: 40
        )
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(workspaceSlug, forHTTPHeaderField: "X-Workspace-Slug")
        if let agentToken, !agentToken.isEmpty {
            request.setValue("Bearer \(agentToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw BackendAPIError.invalidPayload("chat_wake long-poll returned unexpected status")
        }
        struct Envelope: Decodable { let pending: Bool }
        return try decoder.decode(Envelope.self, from: data).pending
    }

    /// Short-poll variant — kept for backwards compatibility. Returns `true` when a wake was pending.
    public func consumeChatWakeIfPending() async throws -> Bool {
        let data = try await performRequest(path: "v1/agent/chat_wake", requiresAgentAuth: true)
        struct Envelope: Decodable { let pending: Bool }
        return try decoder.decode(Envelope.self, from: data).pending
    }

    public func claimNextPendingChatMessage() async throws -> BackendClaimedChatMessage? {
        let data = try await performRequest(
            path: "v1/agent/chat_messages/claim_next",
            method: "POST",
            requiresAgentAuth: true
        )
        let envelope = try decoder.decode(BackendClaimedChatMessageEnvelope.self, from: data)
        guard envelope.pending else { return nil }
        guard let chatThread = envelope.chatThread,
              let chatMessage = envelope.chatMessage else {
            throw BackendAPIError.invalidPayload("claim_next response missing chat thread or message")
        }
        return BackendClaimedChatMessage(
            chatThread: chatThread,
            chatMessage: chatMessage,
            chatMessages: envelope.chatMessages ?? []
        )
    }

    public func completeChatMessage(
        id: UUID,
        assistantContent: String
    ) async throws -> BackendCompletedChatMessage {
        let data = try await performRequest(
            path: "v1/agent/chat_messages/\(id.uuidString)/complete",
            method: "POST",
            jsonBody: [
                "assistant_message": [
                    "content": assistantContent
                ]
            ],
            requiresAgentAuth: true
        )
        let envelope = try decoder.decode(BackendCompletedChatMessageEnvelope.self, from: data)
        return BackendCompletedChatMessage(
            chatMessage: envelope.chatMessage,
            assistantMessage: envelope.assistantMessage
        )
    }

    public func failChatMessage(id: UUID, errorMessage: String) async throws -> BackendChatMessage {
        let data = try await performRequest(
            path: "v1/agent/chat_messages/\(id.uuidString)/fail",
            method: "POST",
            jsonBody: [
                "chat_message": [
                    "error_message": errorMessage
                ]
            ],
            requiresAgentAuth: true
        )
        return try decoder.decode(BackendChatMessageEnvelope.self, from: data).chatMessage
    }

    public func fetchPendingInboundFiles(limit: Int = 100) async throws -> [BackendInboundFile] {
        let data = try await performRequest(
            path: "v1/agent/inbound_files",
            queryItems: [URLQueryItem(name: "limit", value: "\(min(limit, 250))")],
            requiresAgentAuth: true
        )
        return try decoder.decode(BackendInboundFilesEnvelope.self, from: data).inboundFiles
    }

    public func markInboundFileProcessed(id: UUID) async throws -> BackendInboundFile {
        let data = try await performRequest(
            path: "v1/agent/inbound_files/\(id.uuidString)/mark_processed",
            method: "POST",
            requiresAgentAuth: true
        )
        return try decoder.decode(BackendInboundFileEnvelope.self, from: data).inboundFile
    }

    private func performRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        jsonBody: [String: Any]? = nil,
        requiresAgentAuth: Bool = false
    ) async throws -> Data {
        var request = URLRequest(url: try url(for: path, queryItems: queryItems))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(workspaceSlug, forHTTPHeaderField: "X-Workspace-Slug")

        if requiresAgentAuth, let agentToken, !agentToken.isEmpty {
            request.setValue("Bearer \(agentToken)", forHTTPHeaderField: "Authorization")
        }

        if let jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody, options: [.fragmentsAllowed])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAPIError.invalidPayload("missing HTTP response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw BackendAPIError.requestFailed(statusCode: httpResponse.statusCode, body: body)
        }
        return data
    }

    private func url(for path: String, queryItems: [URLQueryItem]) throws -> URL {
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(url: baseURL.appending(path: trimmedPath), resolvingAgainstBaseURL: false) else {
            throw BackendAPIError.invalidBaseURL(path)
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw BackendAPIError.invalidBaseURL(path)
        }
        return url
    }

    private func payloadObject(from payloadJson: String?) throws -> [String: Any] {
        guard let payloadJson, !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [:]
        }
        guard let data = payloadJson.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackendAPIError.invalidPayload("payloadJson must decode to a JSON object")
        }
        return object
    }
}
