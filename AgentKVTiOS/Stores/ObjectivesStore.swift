import Foundation
import Observation

/// Abstraction for remote objective CRUD (enables unit tests with a mock sync layer).
protocol ObjectivesRemoteSyncing: Sendable {
    var isEnabled: Bool { get }
    func fetchObjectivesRemote() async throws -> [IOSBackendObjective]
    func createObjectiveRemote(goal: String, status: String, priority: Int, inboundFileIds: [UUID]) async throws -> IOSBackendObjective
    func fetchObjectiveDetailRemote(id: UUID, viewerProfileId: UUID?) async throws -> IOSBackendObjectiveDetail
    func updateObjectiveRemote(id: UUID, goal: String, status: String, priority: Int) async throws -> IOSBackendObjective
    func submitObjectiveFeedbackRemote(id: UUID, content: String, feedbackKind: String, taskId: UUID?, researchSnapshotId: UUID?) async throws -> IOSBackendSubmitObjectiveFeedbackResult
    func updateObjectiveFeedbackRemote(objectiveId: UUID, feedbackId: UUID, content: String, feedbackKind: String, taskId: UUID?, researchSnapshotId: UUID?) async throws -> IOSBackendSubmitObjectiveFeedbackResult
    func approveObjectiveFeedbackPlanRemote(objectiveId: UUID, feedbackId: UUID) async throws -> IOSBackendSubmitObjectiveFeedbackResult
    func regenerateObjectiveFeedbackPlanRemote(objectiveId: UUID, feedbackId: UUID) async throws -> IOSBackendSubmitObjectiveFeedbackResult
    func submitResearchSnapshotFeedbackRemote(objectiveId: UUID, snapshotId: UUID, createdByProfileId: UUID?, rating: String, reason: String?) async throws -> IOSBackendResearchSnapshotFeedback
    func updateResearchSnapshotFeedbackRemote(objectiveId: UUID, snapshotId: UUID, feedbackId: UUID, createdByProfileId: UUID?, rating: String, reason: String?) async throws -> IOSBackendResearchSnapshotFeedback
    func approveObjectivePlanRemote(id: UUID) async throws -> IOSBackendObjective
    func regenerateObjectivePlanRemote(id: UUID) async throws -> IOSBackendObjective
    func runObjectiveNowRemote(id: UUID) async throws -> IOSBackendObjective
    func resetStuckTasksAndRunObjectiveRemote(id: UUID) async throws -> IOSBackendObjective
    func rerunObjectiveRemote(id: UUID) async throws -> IOSBackendObjective
    func deleteObjectiveRemote(id: UUID) async throws
}

@Observable
final class ObjectivesStore {
    private(set) var objectives: [IOSBackendObjective] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let sync: any ObjectivesRemoteSyncing

    init(sync: any ObjectivesRemoteSyncing = IOSBackendSyncService()) {
        self.sync = sync
    }

    @MainActor
    func refresh() async {
        guard sync.isEnabled else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            objectives = try await sync.fetchObjectivesRemote()
        } catch {
            errorMessage = error.localizedDescription
            IOSRuntimeLog.log("[ObjectivesStore] Refresh failed: \(error)")
        }
    }

    /// Creates an objective on the server and prepends it to the local list.
    @MainActor
    func createObjective(goal: String, status: String = "active", inboundFileIds: [UUID] = []) async throws -> IOSBackendObjective {
        let objective = try await sync.createObjectiveRemote(goal: goal, status: status, priority: 0, inboundFileIds: inboundFileIds)
        upsertObjective(objective)
        return objective
    }

    /// Fetches the full detail (tasks + snapshots) for a single objective.
    func fetchDetail(for id: UUID, viewerProfileId: UUID? = nil) async throws -> IOSBackendObjectiveDetail {
        try await sync.fetchObjectiveDetailRemote(id: id, viewerProfileId: viewerProfileId)
    }

    /// Updates an objective on the server and replaces the local list entry.
    @MainActor
    func updateObjective(id: UUID, goal: String, status: String, priority: Int) async throws -> IOSBackendObjective {
        let updated = try await sync.updateObjectiveRemote(id: id, goal: goal, status: status, priority: priority)
        upsertObjective(updated)
        return updated
    }

    @MainActor
    func submitObjectiveFeedback(
        id: UUID,
        content: String,
        feedbackKind: String,
        taskId: UUID?,
        researchSnapshotId: UUID?
    ) async throws -> IOSBackendSubmitObjectiveFeedbackResult {
        let result = try await sync.submitObjectiveFeedbackRemote(
            id: id,
            content: content,
            feedbackKind: feedbackKind,
            taskId: taskId,
            researchSnapshotId: researchSnapshotId
        )
        upsertObjective(result.objective)
        return result
    }

    @MainActor
    func updateObjectiveFeedback(
        objectiveId: UUID,
        feedbackId: UUID,
        content: String,
        feedbackKind: String,
        taskId: UUID?,
        researchSnapshotId: UUID?
    ) async throws -> IOSBackendSubmitObjectiveFeedbackResult {
        let result = try await sync.updateObjectiveFeedbackRemote(
            objectiveId: objectiveId,
            feedbackId: feedbackId,
            content: content,
            feedbackKind: feedbackKind,
            taskId: taskId,
            researchSnapshotId: researchSnapshotId
        )
        upsertObjective(result.objective)
        return result
    }

    @MainActor
    func approveObjectiveFeedbackPlan(
        objectiveId: UUID,
        feedbackId: UUID
    ) async throws -> IOSBackendSubmitObjectiveFeedbackResult {
        let result = try await sync.approveObjectiveFeedbackPlanRemote(objectiveId: objectiveId, feedbackId: feedbackId)
        upsertObjective(result.objective)
        return result
    }

    func submitResearchSnapshotFeedback(
        objectiveId: UUID,
        snapshotId: UUID,
        createdByProfileId: UUID?,
        rating: String,
        reason: String?
    ) async throws -> IOSBackendResearchSnapshotFeedback {
        try await sync.submitResearchSnapshotFeedbackRemote(
            objectiveId: objectiveId,
            snapshotId: snapshotId,
            createdByProfileId: createdByProfileId,
            rating: rating,
            reason: reason
        )
    }

    func updateResearchSnapshotFeedback(
        objectiveId: UUID,
        snapshotId: UUID,
        feedbackId: UUID,
        createdByProfileId: UUID?,
        rating: String,
        reason: String?
    ) async throws -> IOSBackendResearchSnapshotFeedback {
        try await sync.updateResearchSnapshotFeedbackRemote(
            objectiveId: objectiveId,
            snapshotId: snapshotId,
            feedbackId: feedbackId,
            createdByProfileId: createdByProfileId,
            rating: rating,
            reason: reason
        )
    }

    @MainActor
    func regenerateObjectiveFeedbackPlan(
        objectiveId: UUID,
        feedbackId: UUID
    ) async throws -> IOSBackendSubmitObjectiveFeedbackResult {
        let result = try await sync.regenerateObjectiveFeedbackPlanRemote(objectiveId: objectiveId, feedbackId: feedbackId)
        upsertObjective(result.objective)
        return result
    }

    @MainActor
    func approveObjectivePlan(id: UUID) async throws -> IOSBackendObjective {
        let updated = try await sync.approveObjectivePlanRemote(id: id)
        upsertObjective(updated)
        return updated
    }

    @MainActor
    func regenerateObjectivePlan(id: UUID) async throws -> IOSBackendObjective {
        let updated = try await sync.regenerateObjectivePlanRemote(id: id)
        upsertObjective(updated)
        return updated
    }

    /// Explicitly kicks off planner/task execution for this objective on the server.
    @MainActor
    func runObjectiveNow(id: UUID) async throws -> IOSBackendObjective {
        let updated = try await sync.runObjectiveNowRemote(id: id)
        upsertObjective(updated)
        return updated
    }

    @MainActor
    func resetStuckTasksAndRun(id: UUID) async throws -> IOSBackendObjective {
        let updated = try await sync.resetStuckTasksAndRunObjectiveRemote(id: id)
        upsertObjective(updated)
        return updated
    }

    @MainActor
    func rerunObjective(id: UUID) async throws -> IOSBackendObjective {
        let updated = try await sync.rerunObjectiveRemote(id: id)
        upsertObjective(updated)
        return updated
    }

    /// Deletes an objective on the server and removes it from the local list.
    @MainActor
    func deleteObjective(id: UUID) async throws {
        try await sync.deleteObjectiveRemote(id: id)
        objectives.removeAll { $0.id == id }
    }

    @MainActor
    func upsertObjective(_ objective: IOSBackendObjective) {
        if let idx = objectives.firstIndex(where: { $0.id == objective.id }) {
            objectives[idx] = objective
        } else {
            objectives.insert(objective, at: 0)
        }
        objectives.sort {
            if $0.priority == $1.priority {
                return $0.createdAt > $1.createdAt
            }
            return $0.priority > $1.priority
        }
    }
}
