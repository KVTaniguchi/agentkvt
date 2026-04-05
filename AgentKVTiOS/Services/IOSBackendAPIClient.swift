import Foundation
import Observation

enum IOSBackendAPIError: Error, LocalizedError {
    case invalidBaseURL(String)
    case requestFailed(statusCode: Int, body: String)
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let path):
            return "Invalid backend URL path: \(path)"
        case .requestFailed(let statusCode, let body):
            return "Backend request failed with HTTP \(statusCode): \(body)"
        case .invalidPayload(let message):
            return "Invalid backend payload: \(message)"
        }
    }

    var isNotFound: Bool {
        guard case .requestFailed(let statusCode, _) = self else { return false }
        return statusCode == 404
    }
}

struct IOSBackendFamilyMember: Codable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let deviceId: UUID?
    let displayName: String
    let symbol: String?
    let source: String?
    let createdAt: Date
    let updatedAt: Date
}


enum IOSBackendJSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: IOSBackendJSONValue])
    case array([IOSBackendJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .number(Double(int))
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let object = try? container.decode([String: IOSBackendJSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([IOSBackendJSONValue].self) {
            self = .array(array)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var foundationObject: Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .object(let value):
            return value.mapValues { $0.foundationObject }
        case .array(let value):
            return value.map(\.foundationObject)
        case .null:
            return NSNull()
        }
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
}

struct IOSBackendActionItem: Codable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let ownerProfileId: UUID?
    let title: String
    let systemIntent: String
    let payloadJson: [String: IOSBackendJSONValue]
    let relevanceScore: Double
    let isHandled: Bool
    let handledAt: Date?
    let timestamp: Date
    let createdBy: String?
    let createdAt: Date
    let updatedAt: Date
}

struct IOSBackendAgentLog: Codable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let phase: String
    let content: String
    let metadataJson: [String: IOSBackendJSONValue]
    let toolName: String?
    let timestamp: Date
    let createdAt: Date
    let updatedAt: Date
}

struct IOSBackendLifeContextEntry: Codable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let key: String
    let value: String
    let createdAt: Date
    let updatedAt: Date
}

struct IOSBackendChatThread: Codable, Sendable, Identifiable {
    let id: UUID
    let workspaceId: UUID
    let createdByProfileId: UUID?
    let title: String
    let systemPrompt: String
    let allowedToolIds: [String]
    let latestMessagePreview: String?
    let latestMessageRole: String?
    let latestMessageStatus: String?
    let latestMessageAt: Date?
    let pendingMessageCount: Int
    let messageCount: Int
    let createdAt: Date
    let updatedAt: Date
}

struct IOSBackendChatMessage: Codable, Sendable, Identifiable {
    let id: UUID
    let chatThreadId: UUID
    let role: String
    let content: String
    let status: String
    let errorMessage: String?
    let timestamp: Date
    let authorProfileId: UUID?
    let createdAt: Date
    let updatedAt: Date
}

struct IOSBackendChatThreadDetail: Codable, Sendable {
    let chatThread: IOSBackendChatThread
    let chatMessages: [IOSBackendChatMessage]
}

struct IOSBackendInboundFile: Codable, Sendable, Identifiable {
    let id: UUID
    let workspaceId: UUID
    let uploadedByProfileId: UUID?
    let fileName: String
    let contentType: String?
    let byteSize: Int
    let isProcessed: Bool
    let processedAt: Date?
    let timestamp: Date
    let createdAt: Date
    let updatedAt: Date
    let fileBase64: String?
}

struct IOSBackendObjective: Codable, Sendable, Identifiable {
    let id: UUID
    let workspaceId: UUID
    let goal: String
    let status: String   // "pending" | "active" | "completed" | "archived"
    let priority: Int
    let createdAt: Date
    let updatedAt: Date
}

struct IOSBackendTask: Codable, Sendable, Identifiable {
    let id: UUID
    let objectiveId: UUID
    let description: String
    let status: String   // "pending" | "in_progress" | "completed" | "failed"
    let resultSummary: String?
    let createdAt: Date
    let updatedAt: Date
}

struct IOSBackendResearchSnapshot: Codable, Sendable, Identifiable {
    let id: UUID
    let objectiveId: UUID
    let taskId: UUID?
    let key: String
    let value: String
    let previousValue: String?
    let deltaNote: String?
    let checkedAt: Date
    let createdAt: Date
    let updatedAt: Date
}

struct IOSBackendObjectiveDetail: Codable, Sendable {
    let objective: IOSBackendObjective
    let tasks: [IOSBackendTask]
    let researchSnapshots: [IOSBackendResearchSnapshot]
    let agentLogs: [IOSBackendAgentLog]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        objective = try container.decode(IOSBackendObjective.self, forKey: .objective)
        tasks = try container.decode([IOSBackendTask].self, forKey: .tasks)
        researchSnapshots = try container.decode([IOSBackendResearchSnapshot].self, forKey: .researchSnapshots)
        agentLogs = try container.decodeIfPresent([IOSBackendAgentLog].self, forKey: .agentLogs) ?? []
    }
}

struct IOSBackendBootstrap: Codable, Sendable {
    let familyMembers: [IOSBackendFamilyMember]
    let actionItems: [IOSBackendActionItem]
    let agentLogs: [IOSBackendAgentLog]
    let lifeContextEntries: [IOSBackendLifeContextEntry]
    let pendingActionItemsCount: Int
    let recentAgentLogCount: Int
    let serverTime: Date?
}

private struct IOSBackendFamilyMembersEnvelope: Codable {
    let familyMembers: [IOSBackendFamilyMember]
}

private struct IOSBackendFamilyMemberEnvelope: Codable {
    let familyMember: IOSBackendFamilyMember
}


private struct IOSBackendActionItemsEnvelope: Codable {
    let actionItems: [IOSBackendActionItem]
}

private struct IOSBackendActionItemEnvelope: Codable {
    let actionItem: IOSBackendActionItem
}

private struct IOSBackendAgentLogsEnvelope: Codable {
    let agentLogs: [IOSBackendAgentLog]
}

private struct IOSBackendLifeContextEntriesEnvelope: Codable {
    let lifeContextEntries: [IOSBackendLifeContextEntry]
}

private struct IOSBackendLifeContextEntryEnvelope: Codable {
    let lifeContextEntry: IOSBackendLifeContextEntry
}

private struct IOSBackendChatThreadsEnvelope: Codable {
    let chatThreads: [IOSBackendChatThread]
}

private struct IOSBackendChatThreadEnvelope: Codable {
    let chatThread: IOSBackendChatThread
}

private struct IOSBackendChatMessageEnvelope: Codable {
    let chatMessage: IOSBackendChatMessage
}

private struct IOSBackendInboundFilesEnvelope: Codable {
    let inboundFiles: [IOSBackendInboundFile]
}

private struct IOSBackendInboundFileEnvelope: Codable {
    let inboundFile: IOSBackendInboundFile
}

private struct IOSBackendObjectivesEnvelope: Codable {
    let objectives: [IOSBackendObjective]
}

private struct IOSBackendObjectiveEnvelope: Codable {
    let objective: IOSBackendObjective
}

actor IOSBackendAPIClient {
    let baseURL: URL
    let workspaceSlug: String

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Request paths are `v1/...` relative to the API host. If `AGENTKVT_API_BASE_URL` includes a trailing `/v1`,
    /// resolving `v1/objectives/...` would become `.../v1/v1/...` and return 404.
    private static func normalizeAPIBaseURL(_ url: URL) -> URL {
        var s = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.lowercased().hasSuffix("/v1") {
            s = String(s.dropLast("/v1".count))
            while s.hasSuffix("/") { s.removeLast() }
        }
        return URL(string: s) ?? url
    }

    init(baseURL: URL, workspaceSlug: String, session: URLSession = .shared) {
        self.baseURL = Self.normalizeAPIBaseURL(baseURL)
        self.workspaceSlug = workspaceSlug
        self.session = session

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    func fetchBootstrap() async throws -> IOSBackendBootstrap {
        let data = try await performRequest(path: "v1/bootstrap")
        return try decoder.decode(IOSBackendBootstrap.self, from: data)
    }

    func fetchFamilyMembers() async throws -> [IOSBackendFamilyMember] {
        let data = try await performRequest(path: "v1/family_members")
        return try decoder.decode(IOSBackendFamilyMembersEnvelope.self, from: data).familyMembers
    }

    func createFamilyMember(
        id: UUID,
        displayName: String,
        symbol: String
    ) async throws -> IOSBackendFamilyMember {
        let data = try await performRequest(
            path: "v1/family_members",
            method: "POST",
            jsonBody: [
                "family_member": [
                    "id": id.uuidString,
                    "display_name": displayName,
                    "symbol": symbol
                ]
            ]
        )
        return try decoder.decode(IOSBackendFamilyMemberEnvelope.self, from: data).familyMember
    }

    func fetchActionItems(limit: Int = 200, isHandled: Bool? = nil) async throws -> [IOSBackendActionItem] {
        var path = "v1/action_items?limit=\(limit)"
        if let isHandled {
            path += "&is_handled=\(isHandled)"
        }
        let data = try await performRequest(path: path)
        return try decoder.decode(IOSBackendActionItemsEnvelope.self, from: data).actionItems
    }

    func handleActionItem(id: UUID, handledAt: Date) async throws -> IOSBackendActionItem {
        let data = try await performRequest(
            path: "v1/action_items/\(id.uuidString)/handle",
            method: "POST",
            jsonBody: [
                "action_item": [
                    "handled_at": iso8601(handledAt)
                ]
            ]
        )
        return try decoder.decode(IOSBackendActionItemEnvelope.self, from: data).actionItem
    }

    func fetchAgentLogs(limit: Int = 200) async throws -> [IOSBackendAgentLog] {
        let data = try await performRequest(path: "v1/agent_logs?limit=\(limit)")
        return try decoder.decode(IOSBackendAgentLogsEnvelope.self, from: data).agentLogs
    }

    func fetchLifeContextEntries() async throws -> [IOSBackendLifeContextEntry] {
        let data = try await performRequest(path: "v1/life_context")
        return try decoder.decode(IOSBackendLifeContextEntriesEnvelope.self, from: data).lifeContextEntries
    }

    func upsertLifeContextEntry(
        id: UUID,
        existingKey: String?,
        key: String,
        value: String
    ) async throws -> IOSBackendLifeContextEntry {
        let lookupKey = encodedPathComponent(existingKey ?? key)
        let data = try await performRequest(
            path: "v1/life_context/\(lookupKey)",
            method: "PUT",
            jsonBody: [
                "life_context_entry": [
                    "id": id.uuidString,
                    "key": key,
                    "value": value
                ]
            ]
        )
        return try decoder.decode(IOSBackendLifeContextEntryEnvelope.self, from: data).lifeContextEntry
    }

    func fetchChatThreads() async throws -> [IOSBackendChatThread] {
        let data = try await performRequest(path: "v1/chat_threads")
        return try decoder.decode(IOSBackendChatThreadsEnvelope.self, from: data).chatThreads
    }

    func createChatThread(
        id: UUID,
        title: String = "Assistant",
        createdByProfileId: UUID?
    ) async throws -> IOSBackendChatThread {
        var chatThread: [String: Any] = [
            "id": id.uuidString,
            "title": title
        ]
        if let createdByProfileId {
            chatThread["created_by_profile_id"] = createdByProfileId.uuidString
        }

        let data = try await performRequest(
            path: "v1/chat_threads",
            method: "POST",
            jsonBody: ["chat_thread": chatThread]
        )
        return try decoder.decode(IOSBackendChatThreadEnvelope.self, from: data).chatThread
    }

    func fetchChatThread(id: UUID) async throws -> IOSBackendChatThreadDetail {
        let data = try await performRequest(path: "v1/chat_threads/\(id.uuidString)")
        return try decoder.decode(IOSBackendChatThreadDetail.self, from: data)
    }

    func createChatMessage(
        id: UUID,
        threadId: UUID,
        content: String,
        authorProfileId: UUID?
    ) async throws -> IOSBackendChatMessage {
        var chatMessage: [String: Any] = [
            "id": id.uuidString,
            "content": content
        ]
        if let authorProfileId {
            chatMessage["author_profile_id"] = authorProfileId.uuidString
        }

        let data = try await performRequest(
            path: "v1/chat_threads/\(threadId.uuidString)/chat_messages",
            method: "POST",
            jsonBody: ["chat_message": chatMessage]
        )
        return try decoder.decode(IOSBackendChatMessageEnvelope.self, from: data).chatMessage
    }

    /// Nudges the Mac agent (via server poll) to process pending chat when not on LAN.
    func postChatWake() async throws {
        _ = try await performRequest(path: "v1/chat_wake", method: "POST", jsonBody: [:])
    }

    func fetchInboundFiles(limit: Int = 100) async throws -> [IOSBackendInboundFile] {
        let data = try await performRequest(path: "v1/inbound_files?limit=\(limit)")
        return try decoder.decode(IOSBackendInboundFilesEnvelope.self, from: data).inboundFiles
    }

    func createInboundFile(
        id: UUID,
        fileName: String,
        contentType: String?,
        fileData: Data,
        uploadedByProfileId: UUID?
    ) async throws -> IOSBackendInboundFile {
        var inboundFile: [String: Any] = [
            "id": id.uuidString,
            "file_name": fileName,
            "file_base64": fileData.base64EncodedString()
        ]
        if let contentType, !contentType.isEmpty {
            inboundFile["content_type"] = contentType
        }
        if let uploadedByProfileId {
            inboundFile["uploaded_by_profile_id"] = uploadedByProfileId.uuidString
        }

        let data = try await performRequest(
            path: "v1/inbound_files",
            method: "POST",
            jsonBody: ["inbound_file": inboundFile]
        )
        return try decoder.decode(IOSBackendInboundFileEnvelope.self, from: data).inboundFile
    }

    func fetchObjectives() async throws -> [IOSBackendObjective] {
        let data = try await performRequest(path: "v1/objectives")
        return try decoder.decode(IOSBackendObjectivesEnvelope.self, from: data).objectives
    }

    func createObjective(goal: String, status: String, priority: Int) async throws -> IOSBackendObjective {
        let data = try await performRequest(
            path: "v1/objectives",
            method: "POST",
            jsonBody: ["objective": ["goal": goal, "status": status, "priority": priority]]
        )
        return try decoder.decode(IOSBackendObjectiveEnvelope.self, from: data).objective
    }

    func fetchObjectiveDetail(id: UUID) async throws -> IOSBackendObjectiveDetail {
        let data = try await performRequest(path: "v1/objectives/\(id.uuidString)")
        return try decoder.decode(IOSBackendObjectiveDetail.self, from: data)
    }

    func updateObjective(id: UUID, goal: String, status: String, priority: Int) async throws -> IOSBackendObjective {
        let data = try await performRequest(
            path: "v1/objectives/\(id.uuidString)",
            method: "PATCH",
            jsonBody: ["objective": ["goal": goal, "status": status, "priority": priority]]
        )
        return try decoder.decode(IOSBackendObjectiveEnvelope.self, from: data).objective
    }

    func runObjectiveNow(id: UUID) async throws -> IOSBackendObjective {
        let data = try await performRequest(
            path: "v1/objectives/\(id.uuidString)/run_now",
            method: "POST"
        )
        return try decoder.decode(IOSBackendObjectiveEnvelope.self, from: data).objective
    }

    /// Clears `in_progress` tasks back to `pending`, then dispatches (for stuck webhook/Mac runs).
    func resetStuckTasksAndRunObjective(id: UUID) async throws -> IOSBackendObjective {
        let data = try await performRequest(
            path: "v1/objectives/\(id.uuidString)/reset_stuck_tasks_and_run",
            method: "POST"
        )
        return try decoder.decode(IOSBackendObjectiveEnvelope.self, from: data).objective
    }

    /// Resets every task to `pending` and dispatches — full rerun from the app.
    func rerunObjective(id: UUID) async throws -> IOSBackendObjective {
        let data = try await performRequest(
            path: "v1/objectives/\(id.uuidString)/rerun",
            method: "POST"
        )
        return try decoder.decode(IOSBackendObjectiveEnvelope.self, from: data).objective
    }

    func deleteObjective(id: UUID) async throws {
        _ = try await performRequest(path: "v1/objectives/\(id.uuidString)", method: "DELETE")
    }

    func fetchObjectivePresentation(id: UUID) async throws -> UIPresentation {
        let data = try await performRequest(path: "v1/objectives/\(id.uuidString)/presentation")
        return try decoder.decode(UIPresentation.self, from: data)
    }

    private func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func performRequest(
        path: String,
        method: String = "GET",
        jsonBody: [String: Any]? = nil
    ) async throws -> Data {
        var request = URLRequest(url: try url(for: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(workspaceSlug, forHTTPHeaderField: "X-Workspace-Slug")

        if let jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody, options: [.fragmentsAllowed])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IOSBackendAPIError.invalidPayload("missing HTTP response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw IOSBackendAPIError.requestFailed(statusCode: httpResponse.statusCode, body: body)
        }
        return data
    }

    private func url(for path: String) throws -> URL {
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: trimmedPath, relativeTo: baseURL)?.absoluteURL else {
            throw IOSBackendAPIError.invalidBaseURL(path)
        }
        return url
    }

    private func encodedPathComponent(_ raw: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return raw.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? raw
    }
}

final class IOSBackendSyncService {
    let settings: IOSBackendSettings
    private let client: IOSBackendAPIClient?

    init(settings: IOSBackendSettings = .load()) {
        self.settings = settings
        if let baseURL = settings.apiBaseURL {
            self.client = IOSBackendAPIClient(
                baseURL: baseURL,
                workspaceSlug: settings.workspaceSlug ?? "default"
            )
        } else {
            self.client = nil
        }
    }

    var isEnabled: Bool {
        client != nil
    }

    /// Signals the deployed API so the Mac agent can poll and process pending chat (cellular / off-LAN).
    func notifyChatWakeIfNeeded() async {
        guard let client else { return }
        do {
            try await client.postChatWake()
        } catch {
            IOSRuntimeLog.log("[IOSBackendSync] chat_wake failed: \(error)")
        }
    }

    func fetchBootstrapRemote() async throws -> IOSBackendBootstrap {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.fetchBootstrap()
    }

    func fetchFamilyMembersRemote() async throws -> [IOSBackendFamilyMember] {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.fetchFamilyMembers()
    }

    func createFamilyMemberRemote(
        displayName: String,
        symbol: String
    ) async throws -> IOSBackendFamilyMember {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        let remote = try await client.createFamilyMember(
            id: UUID(),
            displayName: trimmedName,
            symbol: trimmedSymbol
        )
        IOSRuntimeLog.log("[IOSBackendSync] Created backend family member id=\(remote.id.uuidString)")
        return remote
    }

    func fetchAgentLogsRemote(limit: Int = 200) async throws -> [IOSBackendAgentLog] {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.fetchAgentLogs(limit: limit)
    }

    func fetchLifeContextEntriesRemote() async throws -> [IOSBackendLifeContextEntry] {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.fetchLifeContextEntries()
    }

    func saveLifeContextRemote(
        existingEntry: IOSBackendLifeContextEntry?,
        key: String,
        value: String
    ) async throws -> IOSBackendLifeContextEntry {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        let remote = try await client.upsertLifeContextEntry(
            id: existingEntry?.id ?? UUID(),
            existingKey: existingEntry?.key,
            key: normalizedKey,
            value: normalizedValue
        )
        IOSRuntimeLog.log("[IOSBackendSync] Saved life-context key=\(remote.key) via backend.")
        return remote
    }

    // MARK: - Remote passthrough (no SwiftData reconciliation)

    func fetchActionItemsRemote(isHandled: Bool? = nil) async throws -> [IOSBackendActionItem] {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.fetchActionItems(isHandled: isHandled)
    }

    func handleActionItemRemote(id: UUID) async throws {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        _ = try await client.handleActionItem(id: id, handledAt: Date())
    }

    func fetchObjectivesRemote() async throws -> [IOSBackendObjective] {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.fetchObjectives()
    }

    func createObjectiveRemote(goal: String, status: String = "active", priority: Int = 0) async throws -> IOSBackendObjective {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.createObjective(goal: goal, status: status, priority: priority)
    }

    func fetchObjectiveDetailRemote(id: UUID) async throws -> IOSBackendObjectiveDetail {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.fetchObjectiveDetail(id: id)
    }

    func updateObjectiveRemote(id: UUID, goal: String, status: String, priority: Int) async throws -> IOSBackendObjective {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.updateObjective(id: id, goal: goal, status: status, priority: priority)
    }

    func runObjectiveNowRemote(id: UUID) async throws -> IOSBackendObjective {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.runObjectiveNow(id: id)
    }

    func resetStuckTasksAndRunObjectiveRemote(id: UUID) async throws -> IOSBackendObjective {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.resetStuckTasksAndRunObjective(id: id)
    }

    func rerunObjectiveRemote(id: UUID) async throws -> IOSBackendObjective {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.rerunObjective(id: id)
    }

    func deleteObjectiveRemote(id: UUID) async throws {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        try await client.deleteObjective(id: id)
    }

    func fetchObjectivePresentationRemote(id: UUID) async throws -> UIPresentation {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.fetchObjectivePresentation(id: id)
    }

    func fetchChatThreadsRemote() async throws -> [IOSBackendChatThread] {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.fetchChatThreads()
    }

    func createChatThreadRemote(
        title: String = "Assistant",
        createdByProfileId: UUID?
    ) async throws -> IOSBackendChatThread {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.createChatThread(
            id: UUID(),
            title: title,
            createdByProfileId: createdByProfileId
        )
    }

    func fetchChatThreadRemote(id: UUID) async throws -> IOSBackendChatThreadDetail {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.fetchChatThread(id: id)
    }

    func createChatMessageRemote(
        threadId: UUID,
        content: String,
        authorProfileId: UUID?
    ) async throws -> IOSBackendChatMessage {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.createChatMessage(
            id: UUID(),
            threadId: threadId,
            content: content,
            authorProfileId: authorProfileId
        )
    }

    func fetchInboundFilesRemote(limit: Int = 100) async throws -> [IOSBackendInboundFile] {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.fetchInboundFiles(limit: limit)
    }

    func createInboundFileRemote(
        fileName: String,
        contentType: String?,
        fileData: Data,
        uploadedByProfileId: UUID?
    ) async throws -> IOSBackendInboundFile {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.createInboundFile(
            id: UUID(),
            fileName: fileName,
            contentType: contentType,
            fileData: fileData,
            uploadedByProfileId: uploadedByProfileId
        )
    }
}

extension IOSBackendSyncService: ObjectivesRemoteSyncing {}

@Observable
final class FamilyMembersStore {
    private(set) var members: [IOSBackendFamilyMember] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let sync: IOSBackendSyncService

    init(sync: IOSBackendSyncService = IOSBackendSyncService()) {
        self.sync = sync
    }

    @MainActor
    func refresh() async {
        guard sync.isEnabled else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            replaceMembers(try await sync.fetchFamilyMembersRemote())
        } catch {
            errorMessage = error.localizedDescription
            IOSRuntimeLog.log("[FamilyMembersStore] Refresh failed: \(error)")
        }
    }

    @MainActor
    func createFamilyMember(displayName: String, symbol: String) async throws -> IOSBackendFamilyMember {
        let member = try await sync.createFamilyMemberRemote(displayName: displayName, symbol: symbol)
        upsert(member)
        return member
    }

    @MainActor
    func replaceMembers(_ members: [IOSBackendFamilyMember]) {
        self.members = members.sorted { $0.createdAt < $1.createdAt }
        errorMessage = nil
    }

    @MainActor
    private func upsert(_ member: IOSBackendFamilyMember) {
        if let index = members.firstIndex(where: { $0.id == member.id }) {
            members[index] = member
        } else {
            members.append(member)
        }
        members.sort { $0.createdAt < $1.createdAt }
    }
}

@Observable
final class LifeContextStore {
    private(set) var entries: [IOSBackendLifeContextEntry] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let sync: IOSBackendSyncService

    init(sync: IOSBackendSyncService = IOSBackendSyncService()) {
        self.sync = sync
    }

    @MainActor
    func refresh() async {
        guard sync.isEnabled else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            replaceEntries(try await sync.fetchLifeContextEntriesRemote())
        } catch {
            errorMessage = error.localizedDescription
            IOSRuntimeLog.log("[LifeContextStore] Refresh failed: \(error)")
        }
    }

    @MainActor
    func saveEntry(
        existingEntry: IOSBackendLifeContextEntry?,
        key: String,
        value: String
    ) async throws -> IOSBackendLifeContextEntry {
        let saved = try await sync.saveLifeContextRemote(existingEntry: existingEntry, key: key, value: value)
        upsert(saved)
        return saved
    }

    @MainActor
    func replaceEntries(_ entries: [IOSBackendLifeContextEntry]) {
        self.entries = entries.sorted {
            $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
        }
        errorMessage = nil
    }

    @MainActor
    private func upsert(_ entry: IOSBackendLifeContextEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id || $0.key == entry.key }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        entries.sort {
            $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
        }
    }
}

@Observable
final class AgentLogsStore {
    private(set) var logs: [IOSBackendAgentLog] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let sync: IOSBackendSyncService

    init(sync: IOSBackendSyncService = IOSBackendSyncService()) {
        self.sync = sync
    }

    @MainActor
    func refresh(limit: Int = 200) async {
        guard sync.isEnabled else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            replaceLogs(try await sync.fetchAgentLogsRemote(limit: limit))
        } catch {
            errorMessage = error.localizedDescription
            IOSRuntimeLog.log("[AgentLogsStore] Refresh failed: \(error)")
        }
    }

    @MainActor
    func replaceLogs(_ logs: [IOSBackendAgentLog]) {
        self.logs = logs
        errorMessage = nil
    }
}

@Observable
final class ChatStore {
    private(set) var threads: [IOSBackendChatThread] = []
    private(set) var messagesByThreadID: [UUID: [IOSBackendChatMessage]] = [:]
    private(set) var isLoadingThreads = false
    private(set) var loadingThreadIDs: Set<UUID> = []
    private(set) var sendingThreadIDs: Set<UUID> = []
    private(set) var errorMessage: String?

    @ObservationIgnored private let sync: IOSBackendSyncService

    init(sync: IOSBackendSyncService = IOSBackendSyncService()) {
        self.sync = sync
    }

    @MainActor
    func refreshThreads() async {
        guard sync.isEnabled else { return }
        isLoadingThreads = true
        errorMessage = nil
        defer { isLoadingThreads = false }

        do {
            replaceThreads(try await sync.fetchChatThreadsRemote())
        } catch {
            errorMessage = error.localizedDescription
            IOSRuntimeLog.log("[ChatStore] Thread refresh failed: \(error)")
        }
    }

    @MainActor
    func createThread(
        title: String = "Assistant",
        createdByProfileId: UUID?
    ) async throws -> IOSBackendChatThread {
        let thread = try await sync.createChatThreadRemote(
            title: title,
            createdByProfileId: createdByProfileId
        )
        upsertThread(thread)
        return thread
    }

    @MainActor
    func refreshThread(id: UUID) async {
        loadingThreadIDs.insert(id)
        defer { loadingThreadIDs.remove(id) }

        do {
            mergeThreadDetail(try await sync.fetchChatThreadRemote(id: id))
        } catch {
            errorMessage = error.localizedDescription
            IOSRuntimeLog.log("[ChatStore] Thread refresh failed for \(id): \(error)")
        }
    }

    @MainActor
    func sendMessage(
        threadId: UUID,
        content: String,
        authorProfileId: UUID?
    ) async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        sendingThreadIDs.insert(threadId)
        defer { sendingThreadIDs.remove(threadId) }

        let message = try await sync.createChatMessageRemote(
            threadId: threadId,
            content: trimmed,
            authorProfileId: authorProfileId
        )
        upsertMessage(message)

        Task {
            await sync.notifyChatWakeIfNeeded()
            await pollThreadUntilSettled(id: threadId)
        }
    }

    func thread(for id: UUID) -> IOSBackendChatThread? {
        threads.first(where: { $0.id == id })
    }

    func messages(for threadId: UUID) -> [IOSBackendChatMessage] {
        messagesByThreadID[threadId] ?? []
    }

    func hasPendingMessages(threadId: UUID) -> Bool {
        messages(for: threadId).contains { message in
            message.role == "user" && (message.status == "pending" || message.status == "processing")
        }
    }

    private func replaceThreads(_ threads: [IOSBackendChatThread]) {
        self.threads = threads.sorted(by: chatThreadSort)
        errorMessage = nil
    }

    private func mergeThreadDetail(_ detail: IOSBackendChatThreadDetail) {
        upsertThread(detail.chatThread)
        messagesByThreadID[detail.chatThread.id] = detail.chatMessages.sorted {
            if $0.timestamp == $1.timestamp {
                return $0.createdAt < $1.createdAt
            }
            return $0.timestamp < $1.timestamp
        }
        errorMessage = nil
    }

    private func upsertThread(_ thread: IOSBackendChatThread) {
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[index] = thread
        } else {
            threads.append(thread)
        }
        threads.sort(by: chatThreadSort)
    }

    private func upsertMessage(_ message: IOSBackendChatMessage) {
        var threadMessages = messagesByThreadID[message.chatThreadId] ?? []
        if let index = threadMessages.firstIndex(where: { $0.id == message.id }) {
            threadMessages[index] = message
        } else {
            threadMessages.append(message)
        }
        messagesByThreadID[message.chatThreadId] = threadMessages.sorted {
            if $0.timestamp == $1.timestamp {
                return $0.createdAt < $1.createdAt
            }
            return $0.timestamp < $1.timestamp
        }
    }

    @MainActor
    private func pollThreadUntilSettled(id: UUID) async {
        for _ in 0..<15 {
            await refreshThread(id: id)
            if !hasPendingMessages(threadId: id) {
                await refreshThreads()
                return
            }
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
        }
        await refreshThreads()
    }

    private func chatThreadSort(lhs: IOSBackendChatThread, rhs: IOSBackendChatThread) -> Bool {
        if lhs.updatedAt == rhs.updatedAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.updatedAt > rhs.updatedAt
    }
}

@Observable
final class InboundFilesStore {
    private(set) var files: [IOSBackendInboundFile] = []
    private(set) var isLoading = false
    private(set) var isUploading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let sync: IOSBackendSyncService

    init(sync: IOSBackendSyncService = IOSBackendSyncService()) {
        self.sync = sync
    }

    @MainActor
    func refresh(limit: Int = 100) async {
        guard sync.isEnabled else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            replaceFiles(try await sync.fetchInboundFilesRemote(limit: limit))
        } catch {
            errorMessage = error.localizedDescription
            IOSRuntimeLog.log("[InboundFilesStore] Refresh failed: \(error)")
        }
    }

    @MainActor
    func uploadFile(
        fileName: String,
        contentType: String?,
        fileData: Data,
        uploadedByProfileId: UUID?
    ) async throws -> IOSBackendInboundFile {
        isUploading = true
        defer { isUploading = false }

        let inboundFile = try await sync.createInboundFileRemote(
            fileName: fileName,
            contentType: contentType,
            fileData: fileData,
            uploadedByProfileId: uploadedByProfileId
        )
        upsertFile(inboundFile)
        return inboundFile
    }

    func replaceFiles(_ files: [IOSBackendInboundFile]) {
        self.files = files.sorted(by: inboundFileSort)
        errorMessage = nil
    }

    private func upsertFile(_ file: IOSBackendInboundFile) {
        if let index = files.firstIndex(where: { $0.id == file.id }) {
            files[index] = file
        } else {
            files.append(file)
        }
        files.sort(by: inboundFileSort)
    }

    private func inboundFileSort(lhs: IOSBackendInboundFile, rhs: IOSBackendInboundFile) -> Bool {
        if lhs.timestamp == rhs.timestamp {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.timestamp > rhs.timestamp
    }
}
