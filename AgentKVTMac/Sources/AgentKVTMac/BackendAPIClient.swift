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

public struct BackendMission: Codable, Sendable {
    public let id: UUID
    public let workspaceId: UUID
    public let ownerProfileId: UUID?
    public let sourceDeviceId: UUID?
    public let missionName: String
    public let systemPrompt: String
    public let triggerSchedule: String
    public let allowedMcpTools: [String]
    public let isEnabled: Bool
    public let lastRunAt: Date?
    public let runRequestedAt: Date?
    public let sourceUpdatedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    func asRequest() -> MissionRunner.Request {
        MissionRunner.Request(
            id: id,
            missionName: missionName,
            systemPrompt: systemPrompt,
            triggerSchedule: triggerSchedule,
            allowedToolIds: allowedMcpTools,
            ownerProfileId: ownerProfileId,
            isEnabled: isEnabled,
            lastRunAt: lastRunAt
        )
    }
}

public struct BackendActionItem: Codable, Sendable {
    public let id: UUID
    public let workspaceId: UUID
    public let sourceMissionId: UUID?
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
    public let missionId: UUID?
    public let phase: String
    public let content: String
    public let metadataJson: [String: String]
    public let timestamp: Date
    public let createdAt: Date
    public let updatedAt: Date
}

private struct BackendMissionsEnvelope: Codable {
    let missions: [BackendMission]
}

private struct BackendDueMissionsEnvelope: Codable {
    let dueMissions: [BackendMission]
}

private struct BackendMissionEnvelope: Codable {
    let mission: BackendMission
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

public actor BackendAPIClient {
    public let baseURL: URL
    public let workspaceSlug: String
    public let agentToken: String?

    private let session: URLSession
    private let decoder: JSONDecoder
    private let isoFormatter: ISO8601DateFormatter

    public init(
        baseURL: URL,
        workspaceSlug: String,
        agentToken: String? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.workspaceSlug = workspaceSlug
        self.agentToken = agentToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .iso8601
        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.formatOptions = [.withInternetDateTime]
    }

    public func fetchMissions() async throws -> [BackendMission] {
        let data = try await performRequest(path: "v1/missions")
        return try decoder.decode(BackendMissionsEnvelope.self, from: data).missions
    }

    public func fetchDueMissions(at date: Date) async throws -> [BackendMission] {
        let data = try await performRequest(
            path: "v1/agent/due_missions",
            queryItems: [URLQueryItem(name: "at", value: isoFormatter.string(from: date))],
            requiresAgentAuth: true
        )
        return try decoder.decode(BackendDueMissionsEnvelope.self, from: data).dueMissions
    }

    public func fetchUnhandledActionItems(missionId: UUID) async throws -> [BackendActionItem] {
        let data = try await performRequest(
            path: "v1/agent/missions/\(missionId.uuidString)/action_items",
            requiresAgentAuth: true
        )
        return try decoder.decode(BackendActionItemsEnvelope.self, from: data).actionItems
    }

    public func createActionItem(
        missionId: UUID,
        title: String,
        systemIntent: String,
        payloadJson: String?
    ) async throws -> BackendActionItem {
        let actionPayload: [String: Any] = [
            "title": title,
            "system_intent": systemIntent,
            "payload_json": try payloadObject(from: payloadJson),
            "created_by": "mac_agent"
        ]
        let data = try await performRequest(
            path: "v1/agent/missions/\(missionId.uuidString)/action_items",
            method: "POST",
            jsonBody: ["action_item": actionPayload],
            requiresAgentAuth: true
        )
        return try decoder.decode(BackendActionItemEnvelope.self, from: data).actionItem
    }

    public func createLog(
        missionId: UUID,
        phase: String,
        content: String,
        toolName: String? = nil
    ) async throws -> BackendAgentLog {
        var metadata: [String: String] = [:]
        if let toolName, !toolName.isEmpty {
            metadata["tool_name"] = toolName
        }

        let data = try await performRequest(
            path: "v1/agent/missions/\(missionId.uuidString)/logs",
            method: "POST",
            jsonBody: [
                "agent_log": [
                    "phase": phase,
                    "content": content,
                    "metadata_json": metadata
                ]
            ],
            requiresAgentAuth: true
        )
        return try decoder.decode(BackendAgentLogEnvelope.self, from: data).agentLog
    }

    public func markMissionRun(missionId: UUID, at date: Date) async throws -> BackendMission {
        let data = try await performRequest(
            path: "v1/agent/missions/\(missionId.uuidString)/mark_run",
            method: "POST",
            jsonBody: ["ran_at": isoFormatter.string(from: date)],
            requiresAgentAuth: true
        )
        return try decoder.decode(BackendMissionEnvelope.self, from: data).mission
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
