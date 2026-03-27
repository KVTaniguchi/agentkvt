import Foundation
import ManagerCore
import SwiftData

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

struct IOSBackendMission: Codable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let ownerProfileId: UUID?
    let sourceDeviceId: UUID?
    let missionName: String
    let systemPrompt: String
    let triggerSchedule: String
    let allowedMcpTools: [String]
    let isEnabled: Bool
    let lastRunAt: Date?
    let sourceUpdatedAt: Date?
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
    let sourceMissionId: UUID?
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
    let missionId: UUID?
    let missionName: String?
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

struct IOSBackendBootstrap: Codable, Sendable {
    let familyMembers: [IOSBackendFamilyMember]
    let missions: [IOSBackendMission]
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

private struct IOSBackendMissionsEnvelope: Codable {
    let missions: [IOSBackendMission]
}

private struct IOSBackendMissionEnvelope: Codable {
    let mission: IOSBackendMission
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

actor IOSBackendAPIClient {
    let baseURL: URL
    let workspaceSlug: String

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL, workspaceSlug: String, session: URLSession = .shared) {
        self.baseURL = baseURL
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

    func fetchMissions() async throws -> [IOSBackendMission] {
        let data = try await performRequest(path: "v1/missions")
        return try decoder.decode(IOSBackendMissionsEnvelope.self, from: data).missions
    }

    func fetchActionItems(limit: Int = 200) async throws -> [IOSBackendActionItem] {
        let data = try await performRequest(path: "v1/action_items?limit=\(limit)")
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

    func createMission(
        id: UUID,
        missionName: String,
        systemPrompt: String,
        triggerSchedule: String,
        allowedMcpTools: [String],
        ownerProfileId: UUID?,
        isEnabled: Bool,
        lastRunAt: Date?,
        sourceUpdatedAt: Date?
    ) async throws -> IOSBackendMission {
        let data = try await performRequest(
            path: "v1/missions",
            method: "POST",
            jsonBody: [
                "mission": missionPayload(
                    id: id,
                    missionName: missionName,
                    systemPrompt: systemPrompt,
                    triggerSchedule: triggerSchedule,
                    allowedMcpTools: allowedMcpTools,
                    ownerProfileId: ownerProfileId,
                    isEnabled: isEnabled,
                    lastRunAt: lastRunAt,
                    sourceUpdatedAt: sourceUpdatedAt
                )
            ]
        )
        return try decoder.decode(IOSBackendMissionEnvelope.self, from: data).mission
    }

    func updateMission(
        id: UUID,
        missionName: String,
        systemPrompt: String,
        triggerSchedule: String,
        allowedMcpTools: [String],
        ownerProfileId: UUID?,
        isEnabled: Bool,
        lastRunAt: Date?,
        sourceUpdatedAt: Date?
    ) async throws -> IOSBackendMission {
        let data = try await performRequest(
            path: "v1/missions/\(id.uuidString)",
            method: "PATCH",
            jsonBody: [
                "mission": missionPayload(
                    id: id,
                    missionName: missionName,
                    systemPrompt: systemPrompt,
                    triggerSchedule: triggerSchedule,
                    allowedMcpTools: allowedMcpTools,
                    ownerProfileId: ownerProfileId,
                    isEnabled: isEnabled,
                    lastRunAt: lastRunAt,
                    sourceUpdatedAt: sourceUpdatedAt
                )
            ]
        )
        return try decoder.decode(IOSBackendMissionEnvelope.self, from: data).mission
    }

    func deleteMission(id: UUID) async throws {
        _ = try await performRequest(path: "v1/missions/\(id.uuidString)", method: "DELETE")
    }

    private func missionPayload(
        id: UUID,
        missionName: String,
        systemPrompt: String,
        triggerSchedule: String,
        allowedMcpTools: [String],
        ownerProfileId: UUID?,
        isEnabled: Bool,
        lastRunAt: Date?,
        sourceUpdatedAt: Date?
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "id": id.uuidString,
            "mission_name": missionName,
            "system_prompt": systemPrompt,
            "trigger_schedule": triggerSchedule,
            "allowed_mcp_tools": allowedMcpTools,
            "is_enabled": isEnabled
        ]
        payload["owner_profile_id"] = ownerProfileId?.uuidString
        payload["last_run_at"] = lastRunAt.map(iso8601)
        payload["source_updated_at"] = sourceUpdatedAt.map(iso8601)
        return payload
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

    @MainActor
    func bootstrap(modelContext: ModelContext) async {
        guard let client else { return }

        do {
            let snapshot = try await client.fetchBootstrap()
            try reconcileFamilyMembers(snapshot.familyMembers, into: modelContext)
            try reconcileMissions(snapshot.missions, into: modelContext)
            try reconcileActionItems(snapshot.actionItems, into: modelContext)
            try reconcileAgentLogs(snapshot.agentLogs, into: modelContext)
            try reconcileLifeContextEntries(snapshot.lifeContextEntries, into: modelContext)
            try modelContext.save()
            IOSRuntimeLog.log("[IOSBackendSync] Bootstrapped \(snapshot.familyMembers.count) family member(s), \(snapshot.missions.count) mission(s), \(snapshot.actionItems.count) action item(s), \(snapshot.agentLogs.count) log(s), and \(snapshot.lifeContextEntries.count) life-context entry/entries from backend.")
        } catch {
            IOSRuntimeLog.log("[IOSBackendSync] Bootstrap failed: \(error)")
        }
    }

    @MainActor
    func createFamilyMember(
        displayName: String,
        symbol: String,
        modelContext: ModelContext
    ) async throws -> FamilyMember {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)

        if let client {
            let localId = UUID()
            let remote = try await client.createFamilyMember(
                id: localId,
                displayName: trimmedName,
                symbol: trimmedSymbol
            )
            let familyMember = upsertFamilyMember(remote, into: modelContext)
            try modelContext.save()
            IOSRuntimeLog.log("[IOSBackendSync] Created backend family member id=\(familyMember.id.uuidString)")
            return familyMember
        }

        let familyMember = FamilyMember(displayName: trimmedName, symbol: trimmedSymbol)
        modelContext.insert(familyMember)
        try modelContext.save()
        return familyMember
    }

    @MainActor
    func syncMissions(modelContext: ModelContext) async {
        guard let client else { return }

        do {
            let missions = try await client.fetchMissions()
            try reconcileMissions(missions, into: modelContext)
            try modelContext.save()
            IOSRuntimeLog.log("[IOSBackendSync] Synced \(missions.count) mission(s) from backend.")
        } catch {
            IOSRuntimeLog.log("[IOSBackendSync] Mission sync failed: \(error)")
        }
    }

    @MainActor
    func syncActionItems(modelContext: ModelContext) async {
        guard let client else { return }

        do {
            let actionItems = try await client.fetchActionItems()
            try reconcileActionItems(actionItems, into: modelContext)
            try modelContext.save()
            IOSRuntimeLog.log("[IOSBackendSync] Synced \(actionItems.count) action item(s) from backend.")
        } catch {
            IOSRuntimeLog.log("[IOSBackendSync] Action-item sync failed: \(error)")
        }
    }

    @MainActor
    func syncAgentLogs(modelContext: ModelContext) async {
        guard let client else { return }

        do {
            let agentLogs = try await client.fetchAgentLogs()
            try reconcileAgentLogs(agentLogs, into: modelContext)
            try modelContext.save()
            IOSRuntimeLog.log("[IOSBackendSync] Synced \(agentLogs.count) agent log(s) from backend.")
        } catch {
            IOSRuntimeLog.log("[IOSBackendSync] Agent-log sync failed: \(error)")
        }
    }

    @MainActor
    func syncLifeContextEntries(modelContext: ModelContext) async {
        guard let client else { return }

        do {
            let entries = try await client.fetchLifeContextEntries()
            try reconcileLifeContextEntries(entries, into: modelContext)
            try modelContext.save()
            IOSRuntimeLog.log("[IOSBackendSync] Synced \(entries.count) life-context entry/entries from backend.")
        } catch {
            IOSRuntimeLog.log("[IOSBackendSync] Life-context sync failed: \(error)")
        }
    }

    @MainActor
    func saveMission(
        existingMission: MissionDefinition?,
        name: String,
        prompt: String,
        schedule: String,
        tools: [String],
        ownerProfileId: UUID?,
        modelContext: ModelContext
    ) async throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSchedule = schedule.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sourceUpdatedAt = Date()

        if let client {
            let mission: IOSBackendMission
            if let existingMission {
                mission = try await client.updateMission(
                    id: existingMission.id,
                    missionName: normalizedName,
                    systemPrompt: normalizedPrompt,
                    triggerSchedule: normalizedSchedule,
                    allowedMcpTools: tools,
                    ownerProfileId: ownerProfileId,
                    isEnabled: existingMission.isEnabled,
                    lastRunAt: existingMission.lastRunAt,
                    sourceUpdatedAt: sourceUpdatedAt
                )
            } else {
                mission = try await client.createMission(
                    id: UUID(),
                    missionName: normalizedName,
                    systemPrompt: normalizedPrompt,
                    triggerSchedule: normalizedSchedule,
                    allowedMcpTools: tools,
                    ownerProfileId: ownerProfileId,
                    isEnabled: true,
                    lastRunAt: nil,
                    sourceUpdatedAt: sourceUpdatedAt
                )
            }
            _ = upsertMission(mission, into: modelContext)
            try modelContext.save()
            IOSRuntimeLog.log("[IOSBackendSync] Saved mission id=\(mission.id.uuidString) via backend.")
            return
        }

        if let existingMission {
            existingMission.missionName = normalizedName
            existingMission.systemPrompt = normalizedPrompt
            existingMission.triggerSchedule = normalizedSchedule
            existingMission.allowedMCPTools = tools
            existingMission.ownerProfileId = ownerProfileId
            existingMission.updatedAt = sourceUpdatedAt
        } else {
            let mission = MissionDefinition(
                missionName: normalizedName,
                systemPrompt: normalizedPrompt,
                triggerSchedule: normalizedSchedule,
                allowedMCPTools: tools,
                ownerProfileId: ownerProfileId
            )
            mission.updatedAt = sourceUpdatedAt
            modelContext.insert(mission)
        }
        try modelContext.save()
    }

    @MainActor
    func deleteMissions(_ missions: [MissionDefinition], modelContext: ModelContext) async throws {
        if let client {
            for mission in missions {
                try await client.deleteMission(id: mission.id)
            }
        }

        for mission in missions {
            modelContext.delete(mission)
        }
        try modelContext.save()
    }

    @MainActor
    func handleActionItem(
        _ actionItem: ActionItem,
        handledAt: Date = Date(),
        modelContext: ModelContext
    ) async throws {
        if let client {
            let remote = try await client.handleActionItem(id: actionItem.id, handledAt: handledAt)
            _ = upsertActionItem(remote, into: modelContext)
        } else {
            actionItem.isHandled = true
        }
        try modelContext.save()
    }

    @MainActor
    func saveLifeContext(
        existingContext: LifeContext?,
        key: String,
        value: String,
        modelContext: ModelContext
    ) async throws {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if let client {
            let remote = try await client.upsertLifeContextEntry(
                id: existingContext?.id ?? UUID(),
                existingKey: existingContext?.key,
                key: normalizedKey,
                value: normalizedValue
            )
            _ = upsertLifeContextEntry(remote, into: modelContext)
            try modelContext.save()
            IOSRuntimeLog.log("[IOSBackendSync] Saved life-context key=\(remote.key) via backend.")
            return
        }

        if let existingContext {
            existingContext.key = normalizedKey
            existingContext.value = normalizedValue
            existingContext.updatedAt = Date()
        } else {
            modelContext.insert(LifeContext(key: normalizedKey, value: normalizedValue))
        }
        try modelContext.save()
    }

    @MainActor
    private func reconcileFamilyMembers(_ remoteMembers: [IOSBackendFamilyMember], into modelContext: ModelContext) throws {
        for remoteMember in remoteMembers {
            _ = upsertFamilyMember(remoteMember, into: modelContext)
        }
    }

    @MainActor
    private func reconcileMissions(_ remoteMissions: [IOSBackendMission], into modelContext: ModelContext) throws {
        for remoteMission in remoteMissions {
            _ = upsertMission(remoteMission, into: modelContext)
        }
    }

    @MainActor
    private func reconcileActionItems(_ remoteActionItems: [IOSBackendActionItem], into modelContext: ModelContext) throws {
        for remoteActionItem in remoteActionItems {
            _ = upsertActionItem(remoteActionItem, into: modelContext)
        }
        try pruneActionItems(excluding: Set(remoteActionItems.map(\.id)), in: modelContext)
    }

    @MainActor
    private func reconcileAgentLogs(_ remoteAgentLogs: [IOSBackendAgentLog], into modelContext: ModelContext) throws {
        for remoteAgentLog in remoteAgentLogs {
            _ = upsertAgentLog(remoteAgentLog, into: modelContext)
        }
        try pruneAgentLogs(excluding: Set(remoteAgentLogs.map(\.id)), in: modelContext)
    }

    @MainActor
    private func reconcileLifeContextEntries(_ remoteEntries: [IOSBackendLifeContextEntry], into modelContext: ModelContext) throws {
        for remoteEntry in remoteEntries {
            _ = upsertLifeContextEntry(remoteEntry, into: modelContext)
        }
        try pruneLifeContextEntries(excluding: Set(remoteEntries.map(\.id)), in: modelContext)
    }

    @discardableResult
    @MainActor
    private func upsertFamilyMember(_ remoteMember: IOSBackendFamilyMember, into modelContext: ModelContext) -> FamilyMember {
        if let existing = familyMember(id: remoteMember.id, in: modelContext) {
            existing.displayName = remoteMember.displayName
            existing.symbol = remoteMember.symbol ?? ""
            return existing
        }

        let member = FamilyMember(
            id: remoteMember.id,
            displayName: remoteMember.displayName,
            symbol: remoteMember.symbol ?? "",
            createdAt: remoteMember.createdAt
        )
        modelContext.insert(member)
        return member
    }

    @discardableResult
    @MainActor
    private func upsertMission(_ remoteMission: IOSBackendMission, into modelContext: ModelContext) -> MissionDefinition {
        if let existing = mission(id: remoteMission.id, in: modelContext) {
            existing.missionName = remoteMission.missionName
            existing.systemPrompt = remoteMission.systemPrompt
            existing.triggerSchedule = remoteMission.triggerSchedule
            existing.allowedMCPTools = remoteMission.allowedMcpTools
            existing.ownerProfileId = remoteMission.ownerProfileId
            existing.isEnabled = remoteMission.isEnabled
            existing.lastRunAt = remoteMission.lastRunAt
            existing.createdAt = remoteMission.createdAt
            existing.updatedAt = remoteMission.updatedAt
            return existing
        }

        let mission = MissionDefinition(
            id: remoteMission.id,
            missionName: remoteMission.missionName,
            systemPrompt: remoteMission.systemPrompt,
            triggerSchedule: remoteMission.triggerSchedule,
            allowedMCPTools: remoteMission.allowedMcpTools,
            ownerProfileId: remoteMission.ownerProfileId,
            isEnabled: remoteMission.isEnabled,
            lastRunAt: remoteMission.lastRunAt,
            createdAt: remoteMission.createdAt,
            updatedAt: remoteMission.updatedAt
        )
        modelContext.insert(mission)
        return mission
    }

    @discardableResult
    @MainActor
    private func upsertActionItem(_ remoteActionItem: IOSBackendActionItem, into modelContext: ModelContext) -> ActionItem {
        let payloadData = jsonData(from: remoteActionItem.payloadJson)

        if let existing = actionItem(id: remoteActionItem.id, in: modelContext) {
            existing.title = remoteActionItem.title
            existing.systemIntent = remoteActionItem.systemIntent
            existing.payloadData = payloadData
            existing.relevanceScore = remoteActionItem.relevanceScore
            existing.timestamp = remoteActionItem.timestamp
            existing.missionId = remoteActionItem.sourceMissionId
            existing.isHandled = remoteActionItem.isHandled
            existing.createdByProfileId = remoteActionItem.ownerProfileId
            return existing
        }

        let actionItem = ActionItem(
            id: remoteActionItem.id,
            title: remoteActionItem.title,
            systemIntent: remoteActionItem.systemIntent,
            payloadData: payloadData,
            relevanceScore: remoteActionItem.relevanceScore,
            timestamp: remoteActionItem.timestamp,
            missionId: remoteActionItem.sourceMissionId,
            isHandled: remoteActionItem.isHandled,
            createdByProfileId: remoteActionItem.ownerProfileId
        )
        modelContext.insert(actionItem)
        return actionItem
    }

    @discardableResult
    @MainActor
    private func upsertAgentLog(_ remoteAgentLog: IOSBackendAgentLog, into modelContext: ModelContext) -> AgentLog {
        let toolName = remoteAgentLog.toolName ?? remoteAgentLog.metadataJson["tool_name"]?.stringValue

        if let existing = agentLog(id: remoteAgentLog.id, in: modelContext) {
            existing.missionId = remoteAgentLog.missionId
            existing.missionName = remoteAgentLog.missionName
            existing.phase = remoteAgentLog.phase
            existing.content = remoteAgentLog.content
            existing.toolName = toolName
            existing.timestamp = remoteAgentLog.timestamp
            return existing
        }

        let agentLog = AgentLog(
            id: remoteAgentLog.id,
            missionId: remoteAgentLog.missionId,
            missionName: remoteAgentLog.missionName,
            phase: remoteAgentLog.phase,
            content: remoteAgentLog.content,
            toolName: toolName,
            timestamp: remoteAgentLog.timestamp
        )
        modelContext.insert(agentLog)
        return agentLog
    }

    @discardableResult
    @MainActor
    private func upsertLifeContextEntry(_ remoteEntry: IOSBackendLifeContextEntry, into modelContext: ModelContext) -> LifeContext {
        if let existing = lifeContext(id: remoteEntry.id, in: modelContext) ?? lifeContext(key: remoteEntry.key, in: modelContext) {
            existing.id = remoteEntry.id
            existing.key = remoteEntry.key
            existing.value = remoteEntry.value
            existing.updatedAt = remoteEntry.updatedAt
            return existing
        }

        let context = LifeContext(
            id: remoteEntry.id,
            key: remoteEntry.key,
            value: remoteEntry.value,
            updatedAt: remoteEntry.updatedAt
        )
        modelContext.insert(context)
        return context
    }

    @MainActor
    private func familyMember(id: UUID, in modelContext: ModelContext) -> FamilyMember? {
        let descriptor = FetchDescriptor<FamilyMember>(
            predicate: #Predicate<FamilyMember> { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    @MainActor
    private func mission(id: UUID, in modelContext: ModelContext) -> MissionDefinition? {
        let descriptor = FetchDescriptor<MissionDefinition>(
            predicate: #Predicate<MissionDefinition> { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    @MainActor
    private func actionItem(id: UUID, in modelContext: ModelContext) -> ActionItem? {
        let descriptor = FetchDescriptor<ActionItem>(
            predicate: #Predicate<ActionItem> { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    @MainActor
    private func agentLog(id: UUID, in modelContext: ModelContext) -> AgentLog? {
        let descriptor = FetchDescriptor<AgentLog>(
            predicate: #Predicate<AgentLog> { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    @MainActor
    private func lifeContext(id: UUID, in modelContext: ModelContext) -> LifeContext? {
        let descriptor = FetchDescriptor<LifeContext>(
            predicate: #Predicate<LifeContext> { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    @MainActor
    private func lifeContext(key: String, in modelContext: ModelContext) -> LifeContext? {
        let descriptor = FetchDescriptor<LifeContext>(
            predicate: #Predicate<LifeContext> { $0.key == key }
        )
        return try? modelContext.fetch(descriptor).first
    }

    @MainActor
    private func pruneActionItems(excluding remoteIDs: Set<UUID>, in modelContext: ModelContext) throws {
        let localItems = try modelContext.fetch(FetchDescriptor<ActionItem>())
        for localItem in localItems where !remoteIDs.contains(localItem.id) {
            modelContext.delete(localItem)
        }
    }

    @MainActor
    private func pruneAgentLogs(excluding remoteIDs: Set<UUID>, in modelContext: ModelContext) throws {
        let localLogs = try modelContext.fetch(FetchDescriptor<AgentLog>())
        for localLog in localLogs where !remoteIDs.contains(localLog.id) {
            modelContext.delete(localLog)
        }
    }

    @MainActor
    private func pruneLifeContextEntries(excluding remoteIDs: Set<UUID>, in modelContext: ModelContext) throws {
        let localContexts = try modelContext.fetch(FetchDescriptor<LifeContext>())
        for localContext in localContexts where !remoteIDs.contains(localContext.id) {
            modelContext.delete(localContext)
        }
    }

    private func jsonData(from object: [String: IOSBackendJSONValue]) -> Data? {
        guard !object.isEmpty else { return nil }
        return try? JSONSerialization.data(withJSONObject: object.mapValues(\.foundationObject), options: [])
    }
}
