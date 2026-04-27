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

struct IOSBackendWorkspace: Codable, Sendable {
    let id: UUID
    let name: String
    let slug: String
    let serverMode: String
    let agentEmail: String?
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

struct IOSBackendObjectiveBrief: Codable, Sendable, Equatable {
    let context: [String]
    let successCriteria: [String]
    let constraints: [String]
    let preferences: [String]
    let deliverable: String?
    let openQuestions: [String]

    init(
        context: [String] = [],
        successCriteria: [String] = [],
        constraints: [String] = [],
        preferences: [String] = [],
        deliverable: String? = nil,
        openQuestions: [String] = []
    ) {
        self.context = context
        self.successCriteria = successCriteria
        self.constraints = constraints
        self.preferences = preferences
        let trimmedDeliverable = deliverable?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.deliverable = (trimmedDeliverable?.isEmpty == false) ? trimmedDeliverable : nil
        self.openQuestions = openQuestions
    }

    var hasContent: Bool {
        !context.isEmpty ||
        !successCriteria.isEmpty ||
        !constraints.isEmpty ||
        !preferences.isEmpty ||
        deliverable != nil ||
        !openQuestions.isEmpty
    }

    var jsonObject: [String: Any] {
        [
            "context": context,
            "success_criteria": successCriteria,
            "constraints": constraints,
            "preferences": preferences,
            "deliverable": deliverable ?? "",
            "open_questions": openQuestions
        ]
    }
}

struct IOSBackendObjective: Decodable, Sendable, Identifiable, Equatable {
    let id: UUID
    let workspaceId: UUID
    let goal: String
    let status: String   // "pending" | "active" | "completed" | "archived"
    let priority: Int
    let briefJson: IOSBackendObjectiveBrief
    let objectiveKind: String?
    let creationSource: String
    let plannerSummary: String
    let inboundFileIds: [UUID]
    let inProgressTaskCount: Int
    let snapshotCount: Int
    let createdAt: Date
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case workspaceId
        case goal
        case status
        case priority
        case briefJson
        case objectiveKind
        case creationSource
        case plannerSummary
        case inboundFileIds
        case inProgressTaskCount
        case snapshotCount
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        workspaceId = try container.decode(UUID.self, forKey: .workspaceId)
        goal = try container.decode(String.self, forKey: .goal)
        status = try container.decode(String.self, forKey: .status)
        priority = try container.decode(Int.self, forKey: .priority)
        briefJson = try container.decodeIfPresent(IOSBackendObjectiveBrief.self, forKey: .briefJson) ?? .init()
        objectiveKind = try container.decodeIfPresent(String.self, forKey: .objectiveKind)
        creationSource = try container.decodeIfPresent(String.self, forKey: .creationSource) ?? "manual"
        plannerSummary = try container.decodeIfPresent(String.self, forKey: .plannerSummary) ?? goal
        inboundFileIds = try container.decodeIfPresent([UUID].self, forKey: .inboundFileIds) ?? []
        inProgressTaskCount = try container.decodeIfPresent(Int.self, forKey: .inProgressTaskCount) ?? 0
        snapshotCount = try container.decodeIfPresent(Int.self, forKey: .snapshotCount) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct IOSBackendObjectiveDraftMessage: Codable, Sendable, Identifiable {
    let id: UUID
    let objectiveDraftId: UUID
    let role: String
    let content: String
    let timestamp: Date
    let createdAt: Date
    let updatedAt: Date
}

struct IOSBackendObjectiveDraft: Decodable, Sendable, Identifiable {
    let id: UUID
    let workspaceId: UUID
    let createdByProfileId: UUID?
    let finalizedObjectiveId: UUID?
    let status: String
    let templateKey: String
    let briefJson: IOSBackendObjectiveBrief
    let suggestedGoal: String?
    let assistantMessage: String?
    let missingFields: [String]
    let readyToFinalize: Bool
    let plannerSummary: String
    let messages: [IOSBackendObjectiveDraftMessage]
    let createdAt: Date
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case workspaceId
        case createdByProfileId
        case finalizedObjectiveId
        case status
        case templateKey
        case briefJson
        case suggestedGoal
        case assistantMessage
        case missingFields
        case readyToFinalize
        case plannerSummary
        case messages
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        workspaceId = try container.decode(UUID.self, forKey: .workspaceId)
        createdByProfileId = try container.decodeIfPresent(UUID.self, forKey: .createdByProfileId)
        finalizedObjectiveId = try container.decodeIfPresent(UUID.self, forKey: .finalizedObjectiveId)
        status = try container.decode(String.self, forKey: .status)
        templateKey = try container.decode(String.self, forKey: .templateKey)
        briefJson = try container.decodeIfPresent(IOSBackendObjectiveBrief.self, forKey: .briefJson) ?? .init()
        suggestedGoal = try container.decodeIfPresent(String.self, forKey: .suggestedGoal)
        assistantMessage = try container.decodeIfPresent(String.self, forKey: .assistantMessage)
        missingFields = try container.decodeIfPresent([String].self, forKey: .missingFields) ?? []
        readyToFinalize = try container.decodeIfPresent(Bool.self, forKey: .readyToFinalize) ?? false
        plannerSummary = try container.decodeIfPresent(String.self, forKey: .plannerSummary) ?? ""
        messages = try container.decodeIfPresent([IOSBackendObjectiveDraftMessage].self, forKey: .messages) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct IOSBackendFinalizeObjectiveDraftResult: Sendable {
    let objective: IOSBackendObjective
    let objectiveDraft: IOSBackendObjectiveDraft
}

struct IOSBackendTask: Codable, Sendable, Identifiable {
    let id: UUID
    let objectiveId: UUID
    let sourceFeedbackId: UUID?
    let description: String
    let status: String   // "proposed" | "pending" | "in_progress" | "completed" | "failed"
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
    let viewerFeedbackId: UUID?
    let viewerFeedbackRating: String?
    let viewerFeedbackReason: String?
    let goodFeedbackCount: Int
    let badFeedbackCount: Int
    let checkedAt: Date
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID,
        objectiveId: UUID,
        taskId: UUID?,
        key: String,
        value: String,
        previousValue: String?,
        deltaNote: String?,
        viewerFeedbackId: UUID? = nil,
        viewerFeedbackRating: String? = nil,
        viewerFeedbackReason: String? = nil,
        goodFeedbackCount: Int = 0,
        badFeedbackCount: Int = 0,
        checkedAt: Date,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.objectiveId = objectiveId
        self.taskId = taskId
        self.key = key
        self.value = value
        self.previousValue = previousValue
        self.deltaNote = deltaNote
        self.viewerFeedbackId = viewerFeedbackId
        self.viewerFeedbackRating = viewerFeedbackRating
        self.viewerFeedbackReason = viewerFeedbackReason
        self.goodFeedbackCount = goodFeedbackCount
        self.badFeedbackCount = badFeedbackCount
        self.checkedAt = checkedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case objectiveId
        case taskId
        case key
        case value
        case previousValue
        case deltaNote
        case viewerFeedbackId
        case viewerFeedbackRating
        case viewerFeedbackReason
        case goodFeedbackCount
        case badFeedbackCount
        case checkedAt
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        objectiveId = try container.decode(UUID.self, forKey: .objectiveId)
        taskId = try container.decodeIfPresent(UUID.self, forKey: .taskId)
        key = try container.decode(String.self, forKey: .key)
        value = try container.decode(String.self, forKey: .value)
        previousValue = try container.decodeIfPresent(String.self, forKey: .previousValue)
        deltaNote = try container.decodeIfPresent(String.self, forKey: .deltaNote)
        viewerFeedbackId = try container.decodeIfPresent(UUID.self, forKey: .viewerFeedbackId)
        viewerFeedbackRating = try container.decodeIfPresent(String.self, forKey: .viewerFeedbackRating)
        viewerFeedbackReason = try container.decodeIfPresent(String.self, forKey: .viewerFeedbackReason)
        goodFeedbackCount = try container.decodeIfPresent(Int.self, forKey: .goodFeedbackCount) ?? 0
        badFeedbackCount = try container.decodeIfPresent(Int.self, forKey: .badFeedbackCount) ?? 0
        checkedAt = try container.decode(Date.self, forKey: .checkedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct IOSBackendResearchSnapshotFeedback: Codable, Sendable, Identifiable {
    let id: UUID
    let workspaceId: UUID
    let objectiveId: UUID
    let researchSnapshotId: UUID
    let createdByProfileId: UUID?
    let role: String
    let rating: String
    let reason: String?
    let createdAt: Date
    let updatedAt: Date
}

struct IOSBackendObjectiveFeedback: Codable, Sendable, Identifiable {
    let id: UUID
    let objectiveId: UUID
    let taskId: UUID?
    let researchSnapshotId: UUID?
    let role: String
    let feedbackKind: String
    let status: String
    let content: String
    let completionSummary: String?
    let completedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}

struct IOSBackendSubmitObjectiveFeedbackResult: Sendable {
    let objective: IOSBackendObjective
    let objectiveFeedback: IOSBackendObjectiveFeedback
    let followUpTasks: [IOSBackendTask]
}

private struct IOSBackendResearchSnapshotFeedbackEnvelope: Codable {
    let researchSnapshotFeedback: IOSBackendResearchSnapshotFeedback
}

struct IOSBackendObjectiveDetail: Decodable, Sendable {
    let objective: IOSBackendObjective
    let tasks: [IOSBackendTask]
    let researchSnapshots: [IOSBackendResearchSnapshot]
    let objectiveFeedbacks: [IOSBackendObjectiveFeedback]
    let agentLogs: [IOSBackendAgentLog]
    /// Agents that heartbeated recently (server-side); dispatch fails if this stays 0 while using a remote API.
    let onlineAgentRegistrationsCount: Int

    private enum CodingKeys: String, CodingKey {
        case objective
        case tasks
        case researchSnapshots
        case objectiveFeedbacks
        case agentLogs
        case onlineAgentRegistrationsCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        objective = try container.decode(IOSBackendObjective.self, forKey: .objective)
        tasks = try container.decode([IOSBackendTask].self, forKey: .tasks)
        researchSnapshots = try container.decode([IOSBackendResearchSnapshot].self, forKey: .researchSnapshots)
        objectiveFeedbacks = try container.decodeIfPresent([IOSBackendObjectiveFeedback].self, forKey: .objectiveFeedbacks) ?? []
        agentLogs = try container.decodeIfPresent([IOSBackendAgentLog].self, forKey: .agentLogs) ?? []
        onlineAgentRegistrationsCount = try container.decodeIfPresent(Int.self, forKey: .onlineAgentRegistrationsCount) ?? 0
    }
}

struct ObjectiveExecutionHealth: Sendable {
    let hasInProgressWork: Bool
    let hasStalledActiveWork: Bool
    let freshestActiveSilence: TimeInterval?
    let stalestActiveSilence: TimeInterval?
    let staleThreshold: TimeInterval

    private static let defaultStaleThreshold: TimeInterval = 15 * 60

    static func assess(
        objective: IOSBackendObjective,
        tasks: [IOSBackendTask],
        agentLogs: [IOSBackendAgentLog],
        referenceDate: Date = Date()
    ) -> ObjectiveExecutionHealth {
        guard objective.status == "active" else {
            return .init(
                hasInProgressWork: false,
                hasStalledActiveWork: false,
                freshestActiveSilence: nil,
                stalestActiveSilence: nil,
                staleThreshold: defaultStaleThreshold
            )
        }

        let activeTasks = tasks.filter { $0.status == "in_progress" }
        guard !activeTasks.isEmpty else {
            return .init(
                hasInProgressWork: false,
                hasStalledActiveWork: false,
                freshestActiveSilence: nil,
                stalestActiveSilence: nil,
                staleThreshold: defaultStaleThreshold
            )
        }

        let logsByTaskID = groupedLogsByTaskID(agentLogs)
        let activeSilences = activeTasks.map { task in
            max(0, referenceDate.timeIntervalSince(latestActivityDate(for: task, logsByTaskID: logsByTaskID)))
        }
        let staleThreshold = staleThreshold(tasks: tasks, logsByTaskID: logsByTaskID)
        let freshestActiveSilence = activeSilences.min()
        let stalestActiveSilence = activeSilences.max()

        // A task with a recent unclosed worker_claim is actively running LLM inference — not stalled.
        // A claim older than the stale threshold is a dead claim (runner crashed without closing it).
        let anyActivelyRunning = activeTasks.contains {
            hasActiveWorkerClaim(for: $0, logsByTaskID: logsByTaskID, within: staleThreshold, referenceDate: referenceDate)
        }
        let hasStalledActiveWork = !anyActivelyRunning && (freshestActiveSilence ?? 0) >= staleThreshold

        return .init(
            hasInProgressWork: true,
            hasStalledActiveWork: hasStalledActiveWork,
            freshestActiveSilence: freshestActiveSilence,
            stalestActiveSilence: stalestActiveSilence,
            staleThreshold: staleThreshold
        )
    }

    private static func groupedLogsByTaskID(_ agentLogs: [IOSBackendAgentLog]) -> [UUID: [IOSBackendAgentLog]] {
        var grouped: [UUID: [IOSBackendAgentLog]] = [:]
        for log in agentLogs {
            guard let taskID = log.metadataJson["task_id"]?.stringValue.flatMap(UUID.init(uuidString:)) else {
                continue
            }
            grouped[taskID, default: []].append(log)
        }
        return grouped
    }

    private static func latestActivityDate(
        for task: IOSBackendTask,
        logsByTaskID: [UUID: [IOSBackendAgentLog]]
    ) -> Date {
        (logsByTaskID[task.id] ?? []).map(\.timestamp).max() ?? task.updatedAt
    }

    // Returns true when the most recent terminal log for the task is a worker_claim that is
    // recent enough to plausibly still be running LLM inference. A claim older than the stale
    // threshold is treated as a dead claim (runner crashed without closing the work unit).
    private static func hasActiveWorkerClaim(
        for task: IOSBackendTask,
        logsByTaskID: [UUID: [IOSBackendAgentLog]],
        within staleThreshold: TimeInterval,
        referenceDate: Date
    ) -> Bool {
        let logs = (logsByTaskID[task.id] ?? []).sorted { $0.timestamp < $1.timestamp }
        let terminalPhases: Set<String> = ["worker_claim", "worker_complete", "worker_error"]
        guard let lastTerminal = logs.last(where: { terminalPhases.contains($0.phase) }),
              lastTerminal.phase == "worker_claim" else { return false }
        return referenceDate.timeIntervalSince(lastTerminal.timestamp) < staleThreshold
    }

    private static func taskStartDate(
        for task: IOSBackendTask,
        logsByTaskID: [UUID: [IOSBackendAgentLog]]
    ) -> Date {
        let logs = (logsByTaskID[task.id] ?? []).sorted { $0.timestamp < $1.timestamp }
        return logs.first(where: { $0.phase == "worker_claim" })?.timestamp
            ?? logs.first?.timestamp
            ?? task.createdAt
    }

    private static func staleThreshold(
        tasks: [IOSBackendTask],
        logsByTaskID: [UUID: [IOSBackendAgentLog]]
    ) -> TimeInterval {
        let recentCompletedDurations = tasks
            .filter { $0.status == "completed" }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(5)
            .compactMap { task -> TimeInterval? in
                let duration = task.updatedAt.timeIntervalSince(taskStartDate(for: task, logsByTaskID: logsByTaskID))
                guard duration >= 30, duration <= 60 * 90 else { return nil }
                return duration
            }

        guard !recentCompletedDurations.isEmpty else {
            return defaultStaleThreshold
        }

        return max(defaultStaleThreshold, median(recentCompletedDurations) * 3)
    }

    private static func median(_ values: [TimeInterval]) -> TimeInterval {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

// MARK: - Objective guidance (client-side)

struct ObjectiveGuidance {
    enum ActionKind: Equatable {
        case approvePlan
        case reviewFeedback
        case resume
        case planNextSteps
        case allDone
        case monitor
    }

    let buttonLabel: String
    let buttonIcon: String
    let actionKind: ActionKind
    /// Most recent resultSummary from a completed task, for the activity card insight line.
    let lastFinding: String?
    /// Explains why nothing is running; only set when actionKind == .resume.
    let idleReason: String?
}

struct ObjectiveGuidanceProvider {
    static func compute(
        objective: IOSBackendObjective,
        tasks: [IOSBackendTask],
        feedbacks: [IOSBackendObjectiveFeedback],
        snapshots: [IOSBackendResearchSnapshot]
    ) -> ObjectiveGuidance {
        let initialProposed = tasks.filter { $0.status == "proposed" && $0.sourceFeedbackId == nil }.count
        let followUpProposed = tasks.filter { $0.status == "proposed" && $0.sourceFeedbackId != nil }.count
        let pending = tasks.filter { $0.status == "pending" }.count
        let inProgress = tasks.filter { $0.status == "in_progress" }.count
        let completed = tasks.filter { $0.status == "completed" }.count
        let reviewRequired = feedbacks.filter { $0.status == "review_required" }
        let activeFeedbacks = feedbacks.filter { $0.status == "review_required" || $0.status == "approved" }
        let lastFinding = tasks
            .filter { $0.status == "completed" && $0.resultSummary != nil }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first?.resultSummary

        if objective.status == "completed" {
            return .init(buttonLabel: "", buttonIcon: "", actionKind: .allDone,
                         lastFinding: lastFinding, idleReason: nil)
        }
        if initialProposed > 0 {
            return .init(buttonLabel: "Review Plan", buttonIcon: "checklist",
                         actionKind: .approvePlan, lastFinding: lastFinding, idleReason: nil)
        }
        if !reviewRequired.isEmpty {
            return .init(buttonLabel: "Review Follow-up", buttonIcon: "text.badge.plus",
                         actionKind: .reviewFeedback, lastFinding: lastFinding, idleReason: nil)
        }
        if followUpProposed > 0 {
            return .init(buttonLabel: "Review Plan", buttonIcon: "checklist",
                         actionKind: .approvePlan, lastFinding: lastFinding, idleReason: nil)
        }
        if inProgress > 0 || pending > 0 {
            return .init(buttonLabel: "", buttonIcon: "", actionKind: .monitor,
                         lastFinding: lastFinding, idleReason: nil)
        }
        if completed > 0 && activeFeedbacks.isEmpty {
            return .init(buttonLabel: "Plan Next Steps", buttonIcon: "arrow.right.circle",
                         actionKind: .planNextSteps, lastFinding: lastFinding, idleReason: nil)
        }
        if objective.status == "active" {
            return .init(buttonLabel: "Resume", buttonIcon: "play.circle",
                         actionKind: .resume, lastFinding: lastFinding,
                         idleReason: "No tasks are active or pending.")
        }
        return .init(buttonLabel: "", buttonIcon: "", actionKind: .monitor,
                     lastFinding: lastFinding, idleReason: nil)
    }
}

struct IOSBackendBootstrap: Codable, Sendable {
    let workspace: IOSBackendWorkspace?
    let familyMembers: [IOSBackendFamilyMember]
    let lifeContextEntries: [IOSBackendLifeContextEntry]
    let serverTime: Date?
}

private struct IOSBackendFamilyMembersEnvelope: Codable {
    let familyMembers: [IOSBackendFamilyMember]
}

private struct IOSBackendFamilyMemberEnvelope: Codable {
    let familyMember: IOSBackendFamilyMember
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

private struct IOSBackendObjectivesEnvelope: Decodable {
    let objectives: [IOSBackendObjective]
}

private struct IOSBackendObjectiveEnvelope: Decodable {
    let objective: IOSBackendObjective
}

private struct IOSBackendSubmitObjectiveFeedbackEnvelope: Decodable {
    let objective: IOSBackendObjective
    let objectiveFeedback: IOSBackendObjectiveFeedback
    let followUpTasks: [IOSBackendTask]

    private enum CodingKeys: String, CodingKey {
        case objective
        case objectiveFeedback
        case followUpTasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        objective = try container.decode(IOSBackendObjective.self, forKey: .objective)
        objectiveFeedback = try container.decode(IOSBackendObjectiveFeedback.self, forKey: .objectiveFeedback)
        followUpTasks = try container.decodeIfPresent([IOSBackendTask].self, forKey: .followUpTasks) ?? []
    }
}

private struct IOSBackendObjectiveDraftEnvelope: Decodable {
    let objectiveDraft: IOSBackendObjectiveDraft
}

private struct IOSBackendFinalizeObjectiveDraftEnvelope: Decodable {
    let objective: IOSBackendObjective
    let objectiveDraft: IOSBackendObjectiveDraft
}

actor IOSBackendAPIClient {
    private static let defaultRequestTimeout: TimeInterval = 60
    private static let draftRequestTimeout: TimeInterval = 300

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
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func appendField(_ name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("inbound_file[id]", value: id.uuidString)
        appendField("inbound_file[file_name]", value: fileName)
        if let contentType, !contentType.isEmpty {
            appendField("inbound_file[content_type]", value: contentType)
        }
        if let uploadedByProfileId {
            appendField("inbound_file[uploaded_by_profile_id]", value: uploadedByProfileId.uuidString)
        }

        let mimeType = contentType ?? "application/octet-stream"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"inbound_file[file]\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: try url(for: "v1/inbound_files"))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(workspaceSlug, forHTTPHeaderField: "X-Workspace-Slug")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IOSBackendAPIError.invalidPayload("missing HTTP response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw IOSBackendAPIError.requestFailed(statusCode: httpResponse.statusCode, body: responseBody)
        }
        return try decoder.decode(IOSBackendInboundFileEnvelope.self, from: data).inboundFile
    }

    func fetchObjectives() async throws -> [IOSBackendObjective] {
        let data = try await performRequest(path: "v1/objectives")
        return try decoder.decode(IOSBackendObjectivesEnvelope.self, from: data).objectives
    }

    func createObjective(
        goal: String,
        status: String,
        priority: Int,
        objectiveKind: String? = nil,
        creationSource: String? = nil,
        briefJson: IOSBackendObjectiveBrief? = nil,
        inboundFileIds: [UUID] = []
    ) async throws -> IOSBackendObjective {
        var objective: [String: Any] = [
            "goal": goal,
            "status": status,
            "priority": priority
        ]
        if let objectiveKind, !objectiveKind.isEmpty {
            objective["objective_kind"] = objectiveKind
        }
        if let creationSource, !creationSource.isEmpty {
            objective["creation_source"] = creationSource
        }
        if let briefJson {
            objective["brief_json"] = briefJson.jsonObject
        }
        if !inboundFileIds.isEmpty {
            objective["inbound_file_ids"] = inboundFileIds.map(\.uuidString)
        }

        let data = try await performRequest(
            path: "v1/objectives",
            method: "POST",
            jsonBody: ["objective": objective]
        )
        return try decoder.decode(IOSBackendObjectiveEnvelope.self, from: data).objective
    }

    func fetchObjectiveDetail(id: UUID, viewerProfileId: UUID? = nil) async throws -> IOSBackendObjectiveDetail {
        var queryItems: [URLQueryItem] = []
        if let viewerProfileId {
            queryItems.append(URLQueryItem(name: "viewer_profile_id", value: viewerProfileId.uuidString))
        }
        let data = try await performRequest(
            path: "v1/objectives/\(id.uuidString)",
            queryItems: queryItems
        )
        return try decoder.decode(IOSBackendObjectiveDetail.self, from: data)
    }

    func updateObjective(
        id: UUID,
        goal: String,
        status: String,
        priority: Int,
        objectiveKind: String? = nil,
        creationSource: String? = nil,
        briefJson: IOSBackendObjectiveBrief? = nil
    ) async throws -> IOSBackendObjective {
        var objective: [String: Any] = [
            "goal": goal,
            "status": status,
            "priority": priority
        ]
        if let objectiveKind, !objectiveKind.isEmpty {
            objective["objective_kind"] = objectiveKind
        }
        if let creationSource, !creationSource.isEmpty {
            objective["creation_source"] = creationSource
        }
        if let briefJson {
            objective["brief_json"] = briefJson.jsonObject
        }

        let data = try await performRequest(
            path: "v1/objectives/\(id.uuidString)",
            method: "PATCH",
            jsonBody: ["objective": objective]
        )
        return try decoder.decode(IOSBackendObjectiveEnvelope.self, from: data).objective
    }

    func submitObjectiveFeedback(
        id: UUID,
        content: String,
        feedbackKind: String,
        taskId: UUID?,
        researchSnapshotId: UUID?
    ) async throws -> IOSBackendSubmitObjectiveFeedbackResult {
        var objectiveFeedback: [String: Any] = [
            "content": content,
            "feedback_kind": feedbackKind
        ]
        if let taskId {
            objectiveFeedback["task_id"] = taskId.uuidString
        }
        if let researchSnapshotId {
            objectiveFeedback["research_snapshot_id"] = researchSnapshotId.uuidString
        }

        let data = try await performRequest(
            path: "v1/objectives/\(id.uuidString)/feedback",
            method: "POST",
            jsonBody: ["objective_feedback": objectiveFeedback]
        )
        let decoded = try decoder.decode(IOSBackendSubmitObjectiveFeedbackEnvelope.self, from: data)
        return IOSBackendSubmitObjectiveFeedbackResult(
            objective: decoded.objective,
            objectiveFeedback: decoded.objectiveFeedback,
            followUpTasks: decoded.followUpTasks
        )
    }

    func updateObjectiveFeedback(
        objectiveId: UUID,
        feedbackId: UUID,
        content: String,
        feedbackKind: String,
        taskId: UUID?,
        researchSnapshotId: UUID?
    ) async throws -> IOSBackendSubmitObjectiveFeedbackResult {
        var objectiveFeedback: [String: Any] = [
            "content": content,
            "feedback_kind": feedbackKind
        ]
        if let taskId {
            objectiveFeedback["task_id"] = taskId.uuidString
        }
        if let researchSnapshotId {
            objectiveFeedback["research_snapshot_id"] = researchSnapshotId.uuidString
        }

        let data = try await performRequest(
            path: "v1/objectives/\(objectiveId.uuidString)/objective_feedbacks/\(feedbackId.uuidString)",
            method: "PATCH",
            jsonBody: ["objective_feedback": objectiveFeedback]
        )
        let decoded = try decoder.decode(IOSBackendSubmitObjectiveFeedbackEnvelope.self, from: data)
        return IOSBackendSubmitObjectiveFeedbackResult(
            objective: decoded.objective,
            objectiveFeedback: decoded.objectiveFeedback,
            followUpTasks: decoded.followUpTasks
        )
    }

    func approveObjectiveFeedbackPlan(
        objectiveId: UUID,
        feedbackId: UUID
    ) async throws -> IOSBackendSubmitObjectiveFeedbackResult {
        let data = try await performRequest(
            path: "v1/objectives/\(objectiveId.uuidString)/objective_feedbacks/\(feedbackId.uuidString)/approve_plan",
            method: "POST"
        )
        let decoded = try decoder.decode(IOSBackendSubmitObjectiveFeedbackEnvelope.self, from: data)
        return IOSBackendSubmitObjectiveFeedbackResult(
            objective: decoded.objective,
            objectiveFeedback: decoded.objectiveFeedback,
            followUpTasks: decoded.followUpTasks
        )
    }

    func regenerateObjectiveFeedbackPlan(
        objectiveId: UUID,
        feedbackId: UUID
    ) async throws -> IOSBackendSubmitObjectiveFeedbackResult {
        let data = try await performRequest(
            path: "v1/objectives/\(objectiveId.uuidString)/objective_feedbacks/\(feedbackId.uuidString)/regenerate_plan",
            method: "POST"
        )
        let decoded = try decoder.decode(IOSBackendSubmitObjectiveFeedbackEnvelope.self, from: data)
        return IOSBackendSubmitObjectiveFeedbackResult(
            objective: decoded.objective,
            objectiveFeedback: decoded.objectiveFeedback,
            followUpTasks: decoded.followUpTasks
        )
    }

    func submitResearchSnapshotFeedback(
        objectiveId: UUID,
        snapshotId: UUID,
        createdByProfileId: UUID?,
        rating: String,
        reason: String?
    ) async throws -> IOSBackendResearchSnapshotFeedback {
        var feedback: [String: Any] = [
            "rating": rating
        ]
        if let createdByProfileId {
            feedback["created_by_profile_id"] = createdByProfileId.uuidString
        }
        if let reason {
            feedback["reason"] = reason
        }

        let data = try await performRequest(
            path: "v1/objectives/\(objectiveId.uuidString)/research_snapshots/\(snapshotId.uuidString)/feedback",
            method: "POST",
            jsonBody: ["research_snapshot_feedback": feedback]
        )
        return try decoder.decode(IOSBackendResearchSnapshotFeedbackEnvelope.self, from: data).researchSnapshotFeedback
    }

    func updateResearchSnapshotFeedback(
        objectiveId: UUID,
        snapshotId: UUID,
        feedbackId: UUID,
        createdByProfileId: UUID?,
        rating: String,
        reason: String?
    ) async throws -> IOSBackendResearchSnapshotFeedback {
        var feedback: [String: Any] = [
            "rating": rating
        ]
        if let createdByProfileId {
            feedback["created_by_profile_id"] = createdByProfileId.uuidString
        }
        if let reason {
            feedback["reason"] = reason
        }

        let data = try await performRequest(
            path: "v1/objectives/\(objectiveId.uuidString)/research_snapshots/\(snapshotId.uuidString)/feedback/\(feedbackId.uuidString)",
            method: "PATCH",
            jsonBody: ["research_snapshot_feedback": feedback]
        )
        return try decoder.decode(IOSBackendResearchSnapshotFeedbackEnvelope.self, from: data).researchSnapshotFeedback
    }

    func approveObjectivePlan(id: UUID) async throws -> IOSBackendObjective {
        let data = try await performRequest(
            path: "v1/objectives/\(id.uuidString)/approve_plan",
            method: "POST"
        )
        return try decoder.decode(IOSBackendObjectiveEnvelope.self, from: data).objective
    }

    func regenerateObjectivePlan(id: UUID) async throws -> IOSBackendObjective {
        let data = try await performRequest(
            path: "v1/objectives/\(id.uuidString)/regenerate_plan",
            method: "POST"
        )
        return try decoder.decode(IOSBackendObjectiveEnvelope.self, from: data).objective
    }

    func createObjectiveDraft(
        templateKey: String,
        seedText: String?,
        createdByProfileId: UUID?
    ) async throws -> IOSBackendObjectiveDraft {
        var draft: [String: Any] = [
            "template_key": templateKey
        ]
        if let seedText, !seedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft["seed_text"] = seedText
        }
        if let createdByProfileId {
            draft["created_by_profile_id"] = createdByProfileId.uuidString
        }

        let data = try await performRequest(
            path: "v1/objective_drafts",
            method: "POST",
            jsonBody: ["objective_draft": draft],
            timeoutInterval: Self.draftRequestTimeout
        )
        return try decoder.decode(IOSBackendObjectiveDraftEnvelope.self, from: data).objectiveDraft
    }

    func fetchObjectiveDraft(id: UUID) async throws -> IOSBackendObjectiveDraft {
        let data = try await performRequest(path: "v1/objective_drafts/\(id.uuidString)")
        return try decoder.decode(IOSBackendObjectiveDraftEnvelope.self, from: data).objectiveDraft
    }

    func createObjectiveDraftMessage(
        draftId: UUID,
        content: String
    ) async throws -> IOSBackendObjectiveDraft {
        let data = try await performRequest(
            path: "v1/objective_drafts/\(draftId.uuidString)/messages",
            method: "POST",
            jsonBody: [
                "objective_draft_message": [
                    "content": content
                ]
            ],
            timeoutInterval: Self.draftRequestTimeout
        )
        return try decoder.decode(IOSBackendObjectiveDraftEnvelope.self, from: data).objectiveDraft
    }

    func finalizeObjectiveDraft(
        id: UUID,
        goal: String,
        status: String,
        priority: Int,
        briefJson: IOSBackendObjectiveBrief,
        inboundFileIds: [UUID] = []
    ) async throws -> IOSBackendFinalizeObjectiveDraftResult {
        var objectiveDraft: [String: Any] = [
            "goal": goal,
            "status": status,
            "priority": priority,
            "brief_json": briefJson.jsonObject
        ]
        if !inboundFileIds.isEmpty {
            objectiveDraft["inbound_file_ids"] = inboundFileIds.map(\.uuidString)
        }
        let data = try await performRequest(
            path: "v1/objective_drafts/\(id.uuidString)/finalize",
            method: "POST",
            jsonBody: ["objective_draft": objectiveDraft],
            timeoutInterval: Self.draftRequestTimeout
        )
        let decoded = try decoder.decode(IOSBackendFinalizeObjectiveDraftEnvelope.self, from: data)
        return IOSBackendFinalizeObjectiveDraftResult(
            objective: decoded.objective,
            objectiveDraft: decoded.objectiveDraft
        )
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

    private func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func performRequest(
        path: String,
        method: String = "GET",
        jsonBody: [String: Any]? = nil,
        queryItems: [URLQueryItem] = [],
        timeoutInterval: TimeInterval = 60
    ) async throws -> Data {
        var request = URLRequest(url: try url(for: path, queryItems: queryItems))
        request.httpMethod = method
        request.timeoutInterval = timeoutInterval
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

    private func url(for path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var url = URL(string: trimmedPath, relativeTo: baseURL)?.absoluteURL else {
            throw IOSBackendAPIError.invalidBaseURL(path)
        }
        if !queryItems.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw IOSBackendAPIError.invalidBaseURL(path)
            }
            var mergedQueryItems = components.queryItems ?? []
            mergedQueryItems.append(contentsOf: queryItems)
            components.queryItems = mergedQueryItems
            guard let resolvedURL = components.url else {
                throw IOSBackendAPIError.invalidBaseURL(path)
            }
            url = resolvedURL
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


    func fetchObjectivesRemote() async throws -> [IOSBackendObjective] {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.fetchObjectives()
    }

    func createObjectiveRemote(goal: String, status: String = "active", priority: Int = 0, inboundFileIds: [UUID] = []) async throws -> IOSBackendObjective {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.createObjective(goal: goal, status: status, priority: priority, inboundFileIds: inboundFileIds)
    }

    func fetchObjectiveDetailRemote(id: UUID, viewerProfileId: UUID?) async throws -> IOSBackendObjectiveDetail {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.fetchObjectiveDetail(id: id, viewerProfileId: viewerProfileId)
    }

    func updateObjectiveRemote(id: UUID, goal: String, status: String, priority: Int) async throws -> IOSBackendObjective {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.updateObjective(id: id, goal: goal, status: status, priority: priority)
    }

    func submitObjectiveFeedbackRemote(
        id: UUID,
        content: String,
        feedbackKind: String,
        taskId: UUID?,
        researchSnapshotId: UUID?
    ) async throws -> IOSBackendSubmitObjectiveFeedbackResult {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.submitObjectiveFeedback(
            id: id,
            content: content,
            feedbackKind: feedbackKind,
            taskId: taskId,
            researchSnapshotId: researchSnapshotId
        )
    }

    func updateObjectiveFeedbackRemote(
        objectiveId: UUID,
        feedbackId: UUID,
        content: String,
        feedbackKind: String,
        taskId: UUID?,
        researchSnapshotId: UUID?
    ) async throws -> IOSBackendSubmitObjectiveFeedbackResult {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.updateObjectiveFeedback(
            objectiveId: objectiveId,
            feedbackId: feedbackId,
            content: content,
            feedbackKind: feedbackKind,
            taskId: taskId,
            researchSnapshotId: researchSnapshotId
        )
    }

    func approveObjectiveFeedbackPlanRemote(
        objectiveId: UUID,
        feedbackId: UUID
    ) async throws -> IOSBackendSubmitObjectiveFeedbackResult {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.approveObjectiveFeedbackPlan(
            objectiveId: objectiveId,
            feedbackId: feedbackId
        )
    }

    func regenerateObjectiveFeedbackPlanRemote(
        objectiveId: UUID,
        feedbackId: UUID
    ) async throws -> IOSBackendSubmitObjectiveFeedbackResult {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.regenerateObjectiveFeedbackPlan(
            objectiveId: objectiveId,
            feedbackId: feedbackId
        )
    }

    func submitResearchSnapshotFeedbackRemote(
        objectiveId: UUID,
        snapshotId: UUID,
        createdByProfileId: UUID?,
        rating: String,
        reason: String?
    ) async throws -> IOSBackendResearchSnapshotFeedback {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.submitResearchSnapshotFeedback(
            objectiveId: objectiveId,
            snapshotId: snapshotId,
            createdByProfileId: createdByProfileId,
            rating: rating,
            reason: reason
        )
    }

    func updateResearchSnapshotFeedbackRemote(
        objectiveId: UUID,
        snapshotId: UUID,
        feedbackId: UUID,
        createdByProfileId: UUID?,
        rating: String,
        reason: String?
    ) async throws -> IOSBackendResearchSnapshotFeedback {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.updateResearchSnapshotFeedback(
            objectiveId: objectiveId,
            snapshotId: snapshotId,
            feedbackId: feedbackId,
            createdByProfileId: createdByProfileId,
            rating: rating,
            reason: reason
        )
    }

    func approveObjectivePlanRemote(id: UUID) async throws -> IOSBackendObjective {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.approveObjectivePlan(id: id)
    }

    func regenerateObjectivePlanRemote(id: UUID) async throws -> IOSBackendObjective {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.regenerateObjectivePlan(id: id)
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

    func createObjectiveDraftRemote(
        templateKey: String,
        seedText: String? = nil,
        createdByProfileId: UUID?
    ) async throws -> IOSBackendObjectiveDraft {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.createObjectiveDraft(
            templateKey: templateKey,
            seedText: seedText,
            createdByProfileId: createdByProfileId
        )
    }

    func fetchObjectiveDraftRemote(id: UUID) async throws -> IOSBackendObjectiveDraft {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.fetchObjectiveDraft(id: id)
    }

    func createObjectiveDraftMessageRemote(
        draftId: UUID,
        content: String
    ) async throws -> IOSBackendObjectiveDraft {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.createObjectiveDraftMessage(draftId: draftId, content: content)
    }

    func finalizeObjectiveDraftRemote(
        id: UUID,
        goal: String,
        status: String,
        priority: Int,
        briefJson: IOSBackendObjectiveBrief,
        inboundFileIds: [UUID] = []
    ) async throws -> IOSBackendFinalizeObjectiveDraftResult {
        guard let client else { throw IOSBackendAPIError.invalidPayload("Backend not configured") }
        return try await client.finalizeObjectiveDraft(
            id: id,
            goal: goal,
            status: status,
            priority: priority,
            briefJson: briefJson,
            inboundFileIds: inboundFileIds
        )
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
