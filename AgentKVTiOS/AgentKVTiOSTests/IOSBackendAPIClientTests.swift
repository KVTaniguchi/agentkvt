import Foundation
import Testing
@testable import AgentKVTiOS

private final class BackendRequestCaptureURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var requestHandlersByPath: [String: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]
    private static var requestsByPath: [String: URLRequest] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix("example.test") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let key = Self.requestKey(for: request.url), let handler = Self.requestHandler(for: key) else {
            Issue.record("Missing request handler for \(request.url?.absoluteString ?? "<nil>")")
            return
        }

        do {
            Self.record(request, for: key)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BackendRequestCaptureURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func setRequestHandler(
        for key: String,
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        lock.lock()
        requestHandlersByPath[key] = handler
        lock.unlock()
    }

    static func recordedRequest(for key: String) -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requestsByPath[key]
    }

    private static func requestHandler(for key: String) -> ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        lock.lock()
        defer { lock.unlock() }
        return requestHandlersByPath[key]
    }

    private static func record(_ request: URLRequest, for key: String) {
        lock.lock()
        requestsByPath[key] = request
        lock.unlock()
    }

    static func requestKey(host: String, path: String) -> String {
        "\(host)\(path)"
    }

    private static func requestKey(for url: URL?) -> String? {
        guard let url, let host = url.host else { return nil }
        return requestKey(host: host, path: url.path)
    }
}

private func makeDraftEnvelopeData(
    id: UUID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
    status: String = "drafting"
) -> Data {
    let json = """
    {
      "objective_draft": {
        "id": "\(id.uuidString)",
        "workspace_id": "11111111-1111-1111-1111-111111111111",
        "created_by_profile_id": null,
        "finalized_objective_id": null,
        "status": "\(status)",
        "template_key": "household_planning",
        "brief_json": {
          "context": ["Utility bills uploaded"],
          "success_criteria": ["Lower energy costs"],
          "constraints": [],
          "preferences": ["Focus on immediate savings"],
          "deliverable": "Action plan",
          "open_questions": []
        },
        "suggested_goal": "Create an energy-saving action plan.",
        "assistant_message": "What constraints should I respect?",
        "missing_fields": ["constraints"],
        "ready_to_finalize": false,
        "planner_summary": "Goal: Create an energy-saving action plan.",
        "messages": [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "objective_draft_id": "\(id.uuidString)",
            "role": "assistant",
            "content": "What constraints should I respect?",
            "timestamp": "2026-04-09T10:00:00Z",
            "created_at": "2026-04-09T10:00:00Z",
            "updated_at": "2026-04-09T10:00:00Z"
          }
        ],
        "created_at": "2026-04-09T10:00:00Z",
        "updated_at": "2026-04-09T10:01:00Z"
      }
    }
    """
    return Data(json.utf8)
}

private func makeFinalizeEnvelopeData() -> Data {
    let json = """
    {
      "objective": {
        "id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
        "workspace_id": "11111111-1111-1111-1111-111111111111",
        "goal": "Create an energy-saving action plan.",
        "status": "active",
        "priority": 0,
        "brief_json": {
          "context": ["Utility bills uploaded"],
          "success_criteria": ["Lower energy costs"],
          "constraints": ["No major purchases this month"],
          "preferences": ["Focus on immediate savings"],
          "deliverable": "Action plan",
          "open_questions": []
        },
        "objective_kind": "household_planning",
        "creation_source": "guided",
        "planner_summary": "Goal: Create an energy-saving action plan.",
        "created_at": "2026-04-09T10:00:00Z",
        "updated_at": "2026-04-09T10:01:00Z"
      },
      "objective_draft": {
        "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        "workspace_id": "11111111-1111-1111-1111-111111111111",
        "created_by_profile_id": null,
        "finalized_objective_id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
        "status": "finalized",
        "template_key": "household_planning",
        "brief_json": {
          "context": ["Utility bills uploaded"],
          "success_criteria": ["Lower energy costs"],
          "constraints": ["No major purchases this month"],
          "preferences": ["Focus on immediate savings"],
          "deliverable": "Action plan",
          "open_questions": []
        },
        "suggested_goal": "Create an energy-saving action plan.",
        "assistant_message": "This is ready to review.",
        "missing_fields": [],
        "ready_to_finalize": true,
        "planner_summary": "Goal: Create an energy-saving action plan.",
        "messages": [],
        "created_at": "2026-04-09T10:00:00Z",
        "updated_at": "2026-04-09T10:01:00Z"
      }
    }
    """
    return Data(json.utf8)
}

private func makeObjectiveEnvelopeData(
    id: UUID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
    goal: String = "Create an energy-saving action plan.",
    status: String = "active",
    priority: Int = 0
) -> Data {
    let json = """
    {
      "objective": {
        "id": "\(id.uuidString)",
        "workspace_id": "11111111-1111-1111-1111-111111111111",
        "goal": "\(goal)",
        "status": "\(status)",
        "priority": \(priority),
        "brief_json": {
          "context": ["Utility bills uploaded"],
          "success_criteria": ["Lower energy costs"],
          "constraints": ["No major purchases this month"],
          "preferences": ["Focus on immediate savings"],
          "deliverable": "Action plan",
          "open_questions": []
        },
        "objective_kind": "household_planning",
        "creation_source": "guided",
        "planner_summary": "Goal: \(goal)",
        "created_at": "2026-04-09T10:00:00Z",
        "updated_at": "2026-04-09T10:01:00Z"
      }
    }
    """
    return Data(json.utf8)
}

private func makeObjectiveFeedbackSubmitEnvelopeData(
    objectiveId: UUID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
    feedbackId: UUID = UUID(uuidString: "d0d0d0d0-d0d0-d0d0-d0d0-d0d0d0d0d0d0")!
) -> Data {
    let json = """
    {
      "objective": {
        "id": "\(objectiveId.uuidString)",
        "workspace_id": "11111111-1111-1111-1111-111111111111",
        "goal": "Create an energy-saving action plan.",
        "status": "active",
        "priority": 0,
        "created_at": "2026-04-09T10:00:00Z",
        "updated_at": "2026-04-09T10:01:00Z"
      },
      "objective_feedback": {
        "id": "\(feedbackId.uuidString)",
        "objective_id": "\(objectiveId.uuidString)",
        "task_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        "research_snapshot_id": "cccccccc-cccc-cccc-cccc-cccccccccccc",
        "role": "user",
        "feedback_kind": "compare_options",
        "status": "queued",
        "content": "Go deeper on resort fees.",
        "completion_summary": null,
        "completed_at": null,
        "created_at": "2026-04-10T10:00:00Z",
        "updated_at": "2026-04-10T10:01:00Z"
      },
      "follow_up_tasks": [
        {
          "id": "abababab-abab-abab-abab-abababababab",
          "objective_id": "\(objectiveId.uuidString)",
          "source_feedback_id": "\(feedbackId.uuidString)",
          "description": "Compare resort fees for the shortlisted hotels",
          "status": "proposed",
          "result_summary": null,
          "created_at": "2026-04-10T10:00:00Z",
          "updated_at": "2026-04-10T10:01:00Z"
        }
      ]
    }
    """
    return Data(json.utf8)
}

private func makeResponse(
    path: String,
    data: Data
) -> @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) {
    { request in
        let url = try #require(request.url)
        #expect(url.path == path)
        let response = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return (response, data)
    }
}

private func requestBodyData(from request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        throw NSError(domain: "IOSBackendAPIClientTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing request body"])
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
        let bytesRead = stream.read(buffer, maxLength: bufferSize)
        if bytesRead < 0 {
            throw stream.streamError ?? NSError(domain: "IOSBackendAPIClientTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to read request body stream"])
        }
        if bytesRead == 0 {
            break
        }
        data.append(buffer, count: bytesRead)
    }

    return data
}

private func makeClient(host: String) -> IOSBackendAPIClient {
    IOSBackendAPIClient(
        baseURL: URL(string: "http://\(host)")!,
        workspaceSlug: "default",
        session: BackendRequestCaptureURLProtocol.makeSession()
    )
}

@Suite("IOSBackendAPIClient")
struct IOSBackendAPIClientTests {
    @Test("createObjectiveDraft uses the long draft timeout")
    func createObjectiveDraftUsesLongTimeout() async throws {
        let host = "create-draft-\(UUID().uuidString.lowercased()).example.test"
        let path = "/v1/objective_drafts"
        let key = BackendRequestCaptureURLProtocol.requestKey(host: host, path: path)
        BackendRequestCaptureURLProtocol.setRequestHandler(for: key, handler: makeResponse(path: path, data: makeDraftEnvelopeData()))

        let client = makeClient(host: host)
        _ = try await client.createObjectiveDraft(
            templateKey: "household_planning",
            seedText: nil,
            createdByProfileId: nil
        )

        let request = try #require(BackendRequestCaptureURLProtocol.recordedRequest(for: key))
        #expect(request.timeoutInterval == 300)
    }

    @Test("createObjectiveDraftMessage uses the long draft timeout")
    func createObjectiveDraftMessageUsesLongTimeout() async throws {
        let draftID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let host = "create-draft-message-\(UUID().uuidString.lowercased()).example.test"
        let path = "/v1/objective_drafts/\(draftID.uuidString)/messages"
        let key = BackendRequestCaptureURLProtocol.requestKey(host: host, path: path)
        BackendRequestCaptureURLProtocol.setRequestHandler(for: key, handler: makeResponse(path: path, data: makeDraftEnvelopeData(id: draftID)))

        let client = makeClient(host: host)
        _ = try await client.createObjectiveDraftMessage(
            draftId: draftID,
            content: "I want an energy saving plan."
        )

        let request = try #require(BackendRequestCaptureURLProtocol.recordedRequest(for: key))
        #expect(request.timeoutInterval == 300)
    }

    @Test("finalizeObjectiveDraft uses the long draft timeout")
    func finalizeObjectiveDraftUsesLongTimeout() async throws {
        let draftID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let host = "finalize-draft-\(UUID().uuidString.lowercased()).example.test"
        let path = "/v1/objective_drafts/\(draftID.uuidString)/finalize"
        let key = BackendRequestCaptureURLProtocol.requestKey(host: host, path: path)
        BackendRequestCaptureURLProtocol.setRequestHandler(for: key, handler: makeResponse(path: path, data: makeFinalizeEnvelopeData()))

        let client = makeClient(host: host)
        _ = try await client.finalizeObjectiveDraft(
            id: draftID,
            goal: "Create an energy-saving action plan.",
            status: "active",
            priority: 0,
            briefJson: IOSBackendObjectiveBrief(
                context: ["Utility bills uploaded"],
                successCriteria: ["Lower energy costs"],
                constraints: ["No major purchases this month"],
                preferences: ["Focus on immediate savings"],
                deliverable: "Action plan",
                openQuestions: []
            )
        )

        let request = try #require(BackendRequestCaptureURLProtocol.recordedRequest(for: key))
        #expect(request.timeoutInterval == 300)
    }

    @Test("non-draft requests keep the default timeout")
    func nonDraftRequestsUseDefaultTimeout() async throws {
        let json = """
        {
          "objectives": []
        }
        """
        let host = "fetch-objectives-\(UUID().uuidString.lowercased()).example.test"
        let path = "/v1/objectives"
        let key = BackendRequestCaptureURLProtocol.requestKey(host: host, path: path)
        BackendRequestCaptureURLProtocol.setRequestHandler(for: key, handler: makeResponse(path: path, data: Data(json.utf8)))

        let client = makeClient(host: host)
        _ = try await client.fetchObjectives()

        let request = try #require(BackendRequestCaptureURLProtocol.recordedRequest(for: key))
        #expect(request.timeoutInterval == 60)
    }

    @Test("submitObjectiveFeedback posts the content, kind, and anchors")
    func submitObjectiveFeedbackPostsFeedbackPayload() async throws {
        let objectiveID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let taskID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let snapshotID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        let host = "objective-feedback-\(UUID().uuidString.lowercased()).example.test"
        let path = "/v1/objectives/\(objectiveID.uuidString)/feedback"
        let key = BackendRequestCaptureURLProtocol.requestKey(host: host, path: path)
        BackendRequestCaptureURLProtocol.setRequestHandler(
            for: key,
            handler: makeResponse(path: path, data: makeObjectiveFeedbackSubmitEnvelopeData(objectiveId: objectiveID))
        )

        let client = makeClient(host: host)
        let result = try await client.submitObjectiveFeedback(
            id: objectiveID,
            content: "Go deeper on resort fees.",
            feedbackKind: "compare_options",
            taskId: taskID,
            researchSnapshotId: snapshotID
        )

        let request = try #require(BackendRequestCaptureURLProtocol.recordedRequest(for: key))
        let bodyData = try requestBodyData(from: request)
        let jsonObject = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let feedback = try #require(jsonObject["objective_feedback"] as? [String: Any])

        #expect(request.httpMethod == "POST")
        #expect(feedback["content"] as? String == "Go deeper on resort fees.")
        #expect(feedback["feedback_kind"] as? String == "compare_options")
        #expect(feedback["task_id"] as? String == taskID.uuidString)
        #expect(feedback["research_snapshot_id"] as? String == snapshotID.uuidString)
        #expect(result.objective.id == objectiveID)
        #expect(result.objectiveFeedback.feedbackKind == "compare_options")
        #expect(result.objectiveFeedback.taskId == taskID)
        #expect(result.objectiveFeedback.researchSnapshotId == snapshotID)
        #expect(result.followUpTasks.count == 1)
        #expect(result.followUpTasks[0].sourceFeedbackId == result.objectiveFeedback.id)
    }

    @Test("updateObjectiveFeedback patches the feedback payload")
    func updateObjectiveFeedbackPatchesPayload() async throws {
        let objectiveID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let feedbackID = UUID(uuidString: "d0d0d0d0-d0d0-d0d0-d0d0-d0d0d0d0d0d0")!
        let host = "update-objective-feedback-\(UUID().uuidString.lowercased()).example.test"
        let path = "/v1/objectives/\(objectiveID.uuidString)/objective_feedbacks/\(feedbackID.uuidString)"
        let key = BackendRequestCaptureURLProtocol.requestKey(host: host, path: path)
        BackendRequestCaptureURLProtocol.setRequestHandler(
            for: key,
            handler: makeResponse(path: path, data: makeObjectiveFeedbackSubmitEnvelopeData(objectiveId: objectiveID, feedbackId: feedbackID))
        )

        let client = makeClient(host: host)
        let result = try await client.updateObjectiveFeedback(
            objectiveId: objectiveID,
            feedbackId: feedbackID,
            content: "Challenge this finding.",
            feedbackKind: "challenge_result",
            taskId: nil,
            researchSnapshotId: nil
        )

        let request = try #require(BackendRequestCaptureURLProtocol.recordedRequest(for: key))
        let bodyData = try requestBodyData(from: request)
        let jsonObject = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let feedback = try #require(jsonObject["objective_feedback"] as? [String: Any])

        #expect(request.httpMethod == "PATCH")
        #expect(feedback["content"] as? String == "Challenge this finding.")
        #expect(feedback["feedback_kind"] as? String == "challenge_result")
        #expect(result.objectiveFeedback.id == feedbackID)
    }

    @Test("approveObjectiveFeedbackPlan posts to the feedback approval endpoint")
    func approveObjectiveFeedbackPlanPostsToApprovalEndpoint() async throws {
        let objectiveID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let feedbackID = UUID(uuidString: "d0d0d0d0-d0d0-d0d0-d0d0-d0d0d0d0d0d0")!
        let host = "approve-feedback-plan-\(UUID().uuidString.lowercased()).example.test"
        let path = "/v1/objectives/\(objectiveID.uuidString)/objective_feedbacks/\(feedbackID.uuidString)/approve_plan"
        let key = BackendRequestCaptureURLProtocol.requestKey(host: host, path: path)
        BackendRequestCaptureURLProtocol.setRequestHandler(
            for: key,
            handler: makeResponse(path: path, data: makeObjectiveFeedbackSubmitEnvelopeData(objectiveId: objectiveID, feedbackId: feedbackID))
        )

        let client = makeClient(host: host)
        let result = try await client.approveObjectiveFeedbackPlan(objectiveId: objectiveID, feedbackId: feedbackID)

        let request = try #require(BackendRequestCaptureURLProtocol.recordedRequest(for: key))
        #expect(request.httpMethod == "POST")
        #expect(result.objectiveFeedback.id == feedbackID)
    }

    @Test("regenerateObjectiveFeedbackPlan posts to the feedback regenerate endpoint")
    func regenerateObjectiveFeedbackPlanPostsToRegenerateEndpoint() async throws {
        let objectiveID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let feedbackID = UUID(uuidString: "d0d0d0d0-d0d0-d0d0-d0d0-d0d0d0d0d0d0")!
        let host = "regenerate-feedback-plan-\(UUID().uuidString.lowercased()).example.test"
        let path = "/v1/objectives/\(objectiveID.uuidString)/objective_feedbacks/\(feedbackID.uuidString)/regenerate_plan"
        let key = BackendRequestCaptureURLProtocol.requestKey(host: host, path: path)
        BackendRequestCaptureURLProtocol.setRequestHandler(
            for: key,
            handler: makeResponse(path: path, data: makeObjectiveFeedbackSubmitEnvelopeData(objectiveId: objectiveID, feedbackId: feedbackID))
        )

        let client = makeClient(host: host)
        let result = try await client.regenerateObjectiveFeedbackPlan(objectiveId: objectiveID, feedbackId: feedbackID)

        let request = try #require(BackendRequestCaptureURLProtocol.recordedRequest(for: key))
        #expect(request.httpMethod == "POST")
        #expect(result.followUpTasks.count == 1)
    }

    @Test("approveObjectivePlan posts to the approval endpoint")
    func approveObjectivePlanPostsToApprovalEndpoint() async throws {
        let objectiveID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let host = "approve-plan-\(UUID().uuidString.lowercased()).example.test"
        let path = "/v1/objectives/\(objectiveID.uuidString)/approve_plan"
        let key = BackendRequestCaptureURLProtocol.requestKey(host: host, path: path)
        BackendRequestCaptureURLProtocol.setRequestHandler(
            for: key,
            handler: makeResponse(path: path, data: makeObjectiveEnvelopeData(id: objectiveID, goal: "Approved"))
        )

        let client = makeClient(host: host)
        let objective = try await client.approveObjectivePlan(id: objectiveID)

        let request = try #require(BackendRequestCaptureURLProtocol.recordedRequest(for: key))
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 60)
        #expect(objective.id == objectiveID)
        #expect(objective.goal == "Approved")
    }

    @Test("regenerateObjectivePlan posts to the regenerate endpoint")
    func regenerateObjectivePlanPostsToRegenerateEndpoint() async throws {
        let objectiveID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        let host = "regenerate-plan-\(UUID().uuidString.lowercased()).example.test"
        let path = "/v1/objectives/\(objectiveID.uuidString)/regenerate_plan"
        let key = BackendRequestCaptureURLProtocol.requestKey(host: host, path: path)
        BackendRequestCaptureURLProtocol.setRequestHandler(
            for: key,
            handler: makeResponse(path: path, data: makeObjectiveEnvelopeData(id: objectiveID, goal: "Regenerated"))
        )

        let client = makeClient(host: host)
        let objective = try await client.regenerateObjectivePlan(id: objectiveID)

        let request = try #require(BackendRequestCaptureURLProtocol.recordedRequest(for: key))
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 60)
        #expect(objective.id == objectiveID)
        #expect(objective.goal == "Regenerated")
    }
}
