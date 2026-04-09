import Foundation
import Observation

protocol ObjectiveDraftRemoteSyncing: Sendable {
    var isEnabled: Bool { get }
    func createObjectiveDraftRemote(
        templateKey: String,
        seedText: String?,
        createdByProfileId: UUID?
    ) async throws -> IOSBackendObjectiveDraft
    func fetchObjectiveDraftRemote(id: UUID) async throws -> IOSBackendObjectiveDraft
    func createObjectiveDraftMessageRemote(
        draftId: UUID,
        content: String
    ) async throws -> IOSBackendObjectiveDraft
    func finalizeObjectiveDraftRemote(
        id: UUID,
        goal: String,
        status: String,
        priority: Int,
        briefJson: IOSBackendObjectiveBrief
    ) async throws -> IOSBackendFinalizeObjectiveDraftResult
}

enum ObjectiveDraftStoreError: Error, LocalizedError {
    case composerUnavailable
    case noActiveDraft

    var errorDescription: String? {
        switch self {
        case .composerUnavailable:
            return "This server does not support the guided objective composer yet."
        case .noActiveDraft:
            return "No active objective draft is loaded."
        }
    }
}

@Observable
final class ObjectiveDraftStore {
    private static let persistedDraftIDKey = "agentkvt.activeObjectiveDraftID"

    private(set) var activeDraft: IOSBackendObjectiveDraft?
    private(set) var persistedDraftID: UUID?
    private(set) var isStarting = false
    private(set) var isLoading = false
    private(set) var isSending = false
    private(set) var isFinalizing = false
    private(set) var isComposerUnavailable = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let sync: any ObjectiveDraftRemoteSyncing
    @ObservationIgnored private let userDefaults: UserDefaults

    init(
        sync: any ObjectiveDraftRemoteSyncing = IOSBackendSyncService(),
        userDefaults: UserDefaults = .standard
    ) {
        self.sync = sync
        self.userDefaults = userDefaults
        self.persistedDraftID = userDefaults.string(forKey: Self.persistedDraftIDKey).flatMap(UUID.init(uuidString:))
    }

    var isEnabled: Bool {
        sync.isEnabled
    }

    @MainActor
    func reset() {
        setActiveDraft(nil)
        isStarting = false
        isLoading = false
        isSending = false
        isFinalizing = false
        errorMessage = nil
    }

    @MainActor
    func startDraft(
        templateKey: String,
        seedText: String? = nil,
        createdByProfileId: UUID?
    ) async throws -> IOSBackendObjectiveDraft {
        guard sync.isEnabled else {
            throw IOSBackendAPIError.invalidPayload("Backend not configured")
        }

        isStarting = true
        errorMessage = nil
        defer { isStarting = false }

        do {
            let draft = try await sync.createObjectiveDraftRemote(
                templateKey: templateKey,
                seedText: seedText,
                createdByProfileId: createdByProfileId
            )
            setActiveDraft(draft)
            isComposerUnavailable = false
            return draft
        } catch let error as IOSBackendAPIError where error.isNotFound {
            isComposerUnavailable = true
            throw ObjectiveDraftStoreError.composerUnavailable
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    @MainActor
    func refreshDraft(id: UUID? = nil) async {
        let targetID = id ?? activeDraft?.id ?? persistedDraftID
        guard let targetID else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            setActiveDraft(try await sync.fetchObjectiveDraftRemote(id: targetID))
        } catch {
            errorMessage = error.localizedDescription
            IOSRuntimeLog.log("[ObjectiveDraftStore] Refresh failed for \(targetID): \(error)")
        }
    }

    @MainActor
    func sendMessage(_ content: String) async throws -> IOSBackendObjectiveDraft {
        guard let draft = activeDraft else {
            throw ObjectiveDraftStoreError.noActiveDraft
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return draft }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            let updated = try await sync.createObjectiveDraftMessageRemote(
                draftId: draft.id,
                content: trimmed
            )
            setActiveDraft(updated)
            return updated
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    @MainActor
    func finalizeDraft(
        goal: String,
        briefJson: IOSBackendObjectiveBrief,
        startImmediately: Bool
    ) async throws -> IOSBackendObjective {
        guard let draft = activeDraft else {
            throw ObjectiveDraftStoreError.noActiveDraft
        }

        isFinalizing = true
        errorMessage = nil
        defer { isFinalizing = false }

        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let result = try await sync.finalizeObjectiveDraftRemote(
                id: draft.id,
                goal: trimmedGoal,
                status: startImmediately ? "active" : "pending",
                priority: 0,
                briefJson: briefJson
            )
            setActiveDraft(result.objectiveDraft)
            return result.objective
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    @MainActor
    func resumePersistedDraftIfNeeded() async {
        guard activeDraft == nil, persistedDraftID != nil else { return }
        await refreshDraft(id: persistedDraftID)
    }

    @MainActor
    private func setActiveDraft(_ draft: IOSBackendObjectiveDraft?) {
        activeDraft = draft

        if let draft, draft.status == "drafting" {
            persistedDraftID = draft.id
            userDefaults.set(draft.id.uuidString, forKey: Self.persistedDraftIDKey)
        } else {
            persistedDraftID = nil
            userDefaults.removeObject(forKey: Self.persistedDraftIDKey)
        }
    }
}

extension IOSBackendSyncService: ObjectiveDraftRemoteSyncing {}
