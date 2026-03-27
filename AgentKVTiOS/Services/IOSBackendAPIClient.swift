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

struct IOSBackendBootstrap: Codable, Sendable {
    let familyMembers: [IOSBackendFamilyMember]
    let missions: [IOSBackendMission]
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
            try modelContext.save()
            IOSRuntimeLog.log("[IOSBackendSync] Bootstrapped \(snapshot.familyMembers.count) family member(s) and \(snapshot.missions.count) mission(s) from backend.")
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
}
