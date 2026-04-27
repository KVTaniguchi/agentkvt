import Foundation
import Testing
@testable import AgentKVTiOS

private func decodeObjective(_ json: String) throws -> IOSBackendObjective {
    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(IOSBackendObjective.self, from: data)
}

private func decodeDraft(_ json: String) throws -> IOSBackendObjectiveDraft {
    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(IOSBackendObjectiveDraft.self, from: data)
}

private func makeDraft(
    id: UUID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
    templateKey: String = "budget",
    status: String = "drafting",
    readyToFinalize: Bool = false,
    assistantMessage: String = "What budget cap should I plan around?",
    suggestedGoal: String = "Create a monthly family budget.",
    messageContents: [(String, String)] = [("assistant", "What budget cap should I plan around?")]
) throws -> IOSBackendObjectiveDraft {
    let messagesJSON = messageContents.enumerated().map { index, entry in
        """
        {
          "id": "\(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!.uuidString)",
          "objective_draft_id": "\(id.uuidString)",
          "role": "\(entry.0)",
          "content": "\(entry.1.replacingOccurrences(of: "\"", with: "\\\""))",
          "timestamp": "2026-04-09T10:0\(index):00Z",
          "created_at": "2026-04-09T10:0\(index):00Z",
          "updated_at": "2026-04-09T10:0\(index):00Z"
        }
        """
    }.joined(separator: ",")

    let json = """
    {
      "id": "\(id.uuidString)",
      "workspace_id": "11111111-1111-1111-1111-111111111111",
      "created_by_profile_id": "22222222-2222-2222-2222-222222222222",
      "finalized_objective_id": null,
      "status": "\(status)",
      "template_key": "\(templateKey)",
      "brief_json": {
        "context": ["Monthly family budget"],
        "success_criteria": ["Save $500 per month"],
        "constraints": ["Keep dining out under $300"],
        "preferences": ["Simple categories"],
        "deliverable": "Monthly category budget",
        "open_questions": []
      },
      "suggested_goal": "\(suggestedGoal)",
      "assistant_message": "\(assistantMessage.replacingOccurrences(of: "\"", with: "\\\""))",
      "missing_fields": [],
      "ready_to_finalize": \(readyToFinalize ? "true" : "false"),
      "planner_summary": "Goal: \(suggestedGoal)\\nObjective archetype: Budget",
      "messages": [\(messagesJSON)],
      "created_at": "2026-04-09T10:00:00Z",
      "updated_at": "2026-04-09T10:01:00Z"
    }
    """
    return try decodeDraft(json)
}

private func makeObjective(
    id: UUID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
    goal: String = "Create a monthly family budget.",
    status: String = "pending"
) throws -> IOSBackendObjective {
    let json = """
    {
      "id": "\(id.uuidString)",
      "workspace_id": "11111111-1111-1111-1111-111111111111",
      "goal": "\(goal)",
      "status": "\(status)",
      "priority": 0,
      "brief_json": {
        "context": ["Monthly family budget"],
        "success_criteria": ["Save $500 per month"],
        "constraints": ["Keep dining out under $300"],
        "preferences": ["Simple categories"],
        "deliverable": "Monthly category budget",
        "open_questions": []
      },
      "objective_kind": "budget",
      "creation_source": "guided",
      "planner_summary": "Goal: \(goal)\\nObjective archetype: Budget",
      "created_at": "2026-04-09T10:00:00Z",
      "updated_at": "2026-04-09T10:01:00Z"
    }
    """
    return try decodeObjective(json)
}

private final class MockObjectiveDraftSync: ObjectiveDraftRemoteSyncing, @unchecked Sendable {
    var isEnabled = true
    var createResult: Result<IOSBackendObjectiveDraft, Error> = .failure(IOSBackendAPIError.invalidPayload("unset"))
    var fetchResult: Result<IOSBackendObjectiveDraft, Error> = .failure(IOSBackendAPIError.invalidPayload("unset"))
    var sendResult: Result<IOSBackendObjectiveDraft, Error> = .failure(IOSBackendAPIError.invalidPayload("unset"))
    var finalizeResult: Result<IOSBackendFinalizeObjectiveDraftResult, Error> = .failure(IOSBackendAPIError.invalidPayload("unset"))

    func createObjectiveDraftRemote(
        templateKey: String,
        seedText: String?,
        createdByProfileId: UUID?
    ) async throws -> IOSBackendObjectiveDraft {
        try createResult.get()
    }

    func fetchObjectiveDraftRemote(id: UUID) async throws -> IOSBackendObjectiveDraft {
        try fetchResult.get()
    }

    func createObjectiveDraftMessageRemote(
        draftId: UUID,
        content: String
    ) async throws -> IOSBackendObjectiveDraft {
        try sendResult.get()
    }

    func finalizeObjectiveDraftRemote(
        id: UUID,
        goal: String,
        status: String,
        priority: Int,
        briefJson: IOSBackendObjectiveBrief,
        inboundFileIds: [UUID]
    ) async throws -> IOSBackendFinalizeObjectiveDraftResult {
        try finalizeResult.get()
    }
}

private func makeTestUserDefaults() -> UserDefaults {
    let suiteName = "ObjectiveDraftStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@Suite("ObjectiveDraftStore")
struct ObjectiveDraftStoreTests {
    @Test("startDraft stores the returned draft snapshot")
    @MainActor
    func startDraftStoresSnapshot() async throws {
        let draft = try makeDraft()
        let mock = MockObjectiveDraftSync()
        mock.createResult = .success(draft)

        let store = ObjectiveDraftStore(sync: mock, userDefaults: makeTestUserDefaults())
        let started = try await store.startDraft(templateKey: "budget", createdByProfileId: nil)

        #expect(started.id == draft.id)
        #expect(store.activeDraft?.id == draft.id)
        #expect(store.isComposerUnavailable == false)
    }

    @Test("startDraft marks the composer unavailable on a 404 response")
    @MainActor
    func startDraftFallbacksOnMissingEndpoint() async throws {
        let mock = MockObjectiveDraftSync()
        mock.createResult = .failure(IOSBackendAPIError.requestFailed(statusCode: 404, body: "not found"))

        let store = ObjectiveDraftStore(sync: mock, userDefaults: makeTestUserDefaults())

        do {
            _ = try await store.startDraft(templateKey: "budget", createdByProfileId: nil)
            Issue.record("Expected composerUnavailable error")
        } catch ObjectiveDraftStoreError.composerUnavailable {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(store.isComposerUnavailable == true)
    }

    @Test("sendMessage replaces the active draft with the server snapshot")
    @MainActor
    func sendMessageUpdatesDraft() async throws {
        let initial = try makeDraft(
            messageContents: [("assistant", "What budget cap should I plan around?")]
        )
        let updated = try makeDraft(
            readyToFinalize: true,
            assistantMessage: "This is ready to review.",
            messageContents: [
                ("assistant", "What budget cap should I plan around?"),
                ("user", "Keep dining out under $300 and save $500."),
                ("assistant", "This is ready to review.")
            ]
        )
        let mock = MockObjectiveDraftSync()
        mock.createResult = .success(initial)
        mock.sendResult = .success(updated)

        let store = ObjectiveDraftStore(sync: mock, userDefaults: makeTestUserDefaults())
        _ = try await store.startDraft(templateKey: "budget", createdByProfileId: nil)
        let sent = try await store.sendMessage("Keep dining out under $300 and save $500.")

        #expect(sent.messages.count == 3)
        #expect(store.activeDraft?.readyToFinalize == true)
    }

    @Test("finalizeDraft returns the objective and keeps the finalized draft snapshot")
    @MainActor
    func finalizeDraftReturnsObjective() async throws {
        let draft = try makeDraft(readyToFinalize: true)
        let finalizedDraft = try makeDraft(
            status: "finalized",
            readyToFinalize: true,
            assistantMessage: "This is ready to review."
        )
        let objective = try makeObjective(status: "active")
        let mock = MockObjectiveDraftSync()
        mock.createResult = .success(draft)
        mock.finalizeResult = .success(
            IOSBackendFinalizeObjectiveDraftResult(
                objective: objective,
                objectiveDraft: finalizedDraft
            )
        )

        let store = ObjectiveDraftStore(sync: mock, userDefaults: makeTestUserDefaults())
        _ = try await store.startDraft(templateKey: "budget", createdByProfileId: nil)
        let finalized = try await store.finalizeDraft(
            goal: objective.goal,
            briefJson: draft.briefJson,
            startImmediately: true
        )

        #expect(finalized.status == "active")
        #expect(store.activeDraft?.status == "finalized")
    }

    @Test("planner summary builder mirrors the review summary format")
    func plannerSummaryBuilderIncludesKeySections() {
        let summary = IOSObjectivePlannerSummaryBuilder.summary(
            goal: "Plan a Brooklyn date night",
            templateKey: "date_night",
            brief: IOSBackendObjectiveBrief(
                context: ["Friday night in Brooklyn"],
                successCriteria: ["Dinner and one activity"],
                constraints: ["Stay under $180"],
                preferences: ["Cozy places"],
                deliverable: "Recommended plan with backup option",
                openQuestions: []
            )
        )

        #expect(summary.contains("Goal: Plan a Brooklyn date night"))
        #expect(summary.contains("Objective archetype: Date Night"))
        #expect(summary.contains("Constraints:"))
        #expect(summary.contains("Deliverable:"))
    }
}
