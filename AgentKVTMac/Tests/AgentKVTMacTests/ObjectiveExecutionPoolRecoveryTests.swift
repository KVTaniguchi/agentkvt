import Foundation
import SwiftData
import Testing
@testable import AgentKVTMac
@testable import ManagerCore

/// Slow client to exercise supervisor timeout paths.
private final class HangingOllamaClient: OllamaClientProtocol, @unchecked Sendable {
    func chat(
        messages: [OllamaClient.Message],
        tools: [OllamaClient.ToolDef]?
    ) async throws -> OllamaClient.Message {
        try await Task.sleep(for: .seconds(5))
        return .init(role: "assistant", content: "Delayed response", toolCalls: nil)
    }
}

private final class ObjectiveExecutionBackendURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix("example.test") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let host = request.url?.host,
            let handler = Self.currentHandler(forHost: host)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
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
        configuration.protocolClasses = [ObjectiveExecutionBackendURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func setHandler(
        forHost host: String,
        _ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        lock.lock()
        handlers[host] = handler
        lock.unlock()
    }

    static func reset(host: String) {
        lock.lock()
        handlers.removeValue(forKey: host)
        lock.unlock()
    }

    private static func currentHandler(forHost host: String) -> ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[host]
    }
}

private final class BackendStubState: @unchecked Sendable {
    private let lock = NSLock()
    private var synthesisSnapshotWriteAttempts = 0
    private var agentLogContents: [String] = []
    private var failedTaskMessages: [String] = []

    private func requestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var data = Data()
        while stream.hasBytesAvailable {
            let readCount = stream.read(buffer, maxLength: bufferSize)
            guard readCount > 0 else { break }
            data.append(buffer, count: readCount)
        }
        return data.isEmpty ? nil : data
    }

    func nextSynthesisSnapshotWriteAttempt() -> Int {
        lock.lock()
        defer { lock.unlock() }
        synthesisSnapshotWriteAttempts += 1
        return synthesisSnapshotWriteAttempts
    }

    func synthesisSnapshotWriteAttemptsSnapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return synthesisSnapshotWriteAttempts
    }

    @discardableResult
    func recordAgentLogContent(from request: URLRequest) -> String? {
        guard
            let data = requestBodyData(from: request),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let log = object["agent_log"] as? [String: Any],
            let content = log["content"] as? String
        else {
            return nil
        }

        lock.lock()
        agentLogContents.append(content)
        lock.unlock()
        return content
    }

    func agentLogContentsSnapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return agentLogContents
    }

    func recordFailedTaskMessage(from request: URLRequest) -> String? {
        guard
            let data = requestBodyData(from: request),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let message: String? = {
            if let task = object["task"] as? [String: Any] {
                return task["error_message"] as? String ?? task["errorMessage"] as? String
            }
            if let task = object["task"] as? [String: String] {
                return task["error_message"] ?? task["errorMessage"]
            }
            if let task = object["task"] as? NSDictionary {
                return task["error_message"] as? String ?? task["errorMessage"] as? String
            }
            return nil
        }()

        guard let message else { return nil }
        lock.lock()
        failedTaskMessages.append(message)
        lock.unlock()
        return message
    }

    func failedTaskMessagesSnapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return failedTaskMessages
    }
}

private func makeContainer() throws -> (ModelContainer, ModelContext) {
    let schema = Schema([
        LifeContext.self,
        AgentLog.self,
        InboundFile.self,
        ChatThread.self,
        ChatMessage.self,

        WorkUnit.self,
        EphemeralPin.self,
        ResourceHealth.self,
        FamilyMember.self,
        ResearchSnapshot.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    return (container, ModelContext(container))
}

private func makePool<C: OllamaClientProtocol & Sendable>(
    container: ModelContainer,
    context: ModelContext,
    client: C,
    backendClient: BackendAPIClient? = nil,
    timeoutSeconds: TimeInterval
) -> ObjectiveExecutionPool {
    let registry = ToolRegistry()
    let taskRunner = AgentTaskRunner(modelContext: context, client: client, registry: registry)
    return ObjectiveExecutionPool(
        modelContainer: container,
        client: client,
        taskRunner: taskRunner,
        backendClient: backendClient,
        maxConcurrentWorkers: 1,
        researchSettleTimeoutSeconds: timeoutSeconds
    )
}

private func payloadData(
    objectiveId: UUID,
    taskId: UUID,
    taskDescription: String
) throws -> Data {
    let json: [String: Any?] = [
        "objectiveId": objectiveId.uuidString,
        "taskId": taskId.uuidString,
        "rootTaskDescription": taskDescription,
        "parentObjectiveGoal": nil,
        "workDescription": "Research subtask",
        "planningRound": 1,
        "workType": "objective_research",
        "resultSummary": nil,
        "lastError": nil,
    ]
    return try JSONSerialization.data(withJSONObject: json.compactMapValues { $0 }, options: [])
}

private func taskSearchJSON(
    taskId: UUID,
    objectiveId: UUID,
    description: String,
    objectiveGoal: String? = nil
) -> String {
    var payload: [String: Any] = [
        "agentkvt": "run_task_search",
        "task_id": taskId.uuidString,
        "objective_id": objectiveId.uuidString,
        "description": description
    ]
    if let objectiveGoal {
        payload["objective_goal"] = objectiveGoal
    }
    let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

private func makeAgentLogEnvelopeData(request: URLRequest) -> Data {
    let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
    let log = body?["agent_log"] as? [String: Any]
    let phase = log?["phase"] as? String ?? "unknown"
    let content = log?["content"] as? String ?? ""
    let metadata = log?["metadata_json"] as? [String: String] ?? [:]
    let contentJSON = String(
        data: try! JSONSerialization.data(withJSONObject: content, options: [.fragmentsAllowed]),
        encoding: .utf8
    )!
    let json = """
    {
      "agent_log": {
        "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        "workspace_id": "11111111-1111-1111-1111-111111111111",
        "phase": "\(phase)",
        "content": \(contentJSON),
        "metadata_json": \(String(data: try! JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]), encoding: .utf8)!),
        "timestamp": "2026-04-12T18:00:00Z",
        "created_at": "2026-04-12T18:00:00Z",
        "updated_at": "2026-04-12T18:00:00Z"
      }
    }
    """
    return Data(json.utf8)
}

private func makeResearchSnapshotsEnvelopeData() -> Data {
    Data(#"{"research_snapshots":[]}"#.utf8)
}

private func makeResearchSnapshotEnvelopeData(
    request: URLRequest,
    objectiveId: UUID
) -> Data {
    let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
    let taskId = components?.queryItems?.first(where: { $0.name == "task_id" })?.value ?? UUID().uuidString
    let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
    let snapshot = body?["research_snapshot"] as? [String: Any]
    let key = snapshot?["key"] as? String ?? "task_summary_test"
    let value = snapshot?["value"] as? String ?? "Recovered summary"
    let valueJSON = String(
        data: try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
        encoding: .utf8
    )!
    let json = """
    {
      "research_snapshot": {
        "id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
        "objective_id": "\(objectiveId.uuidString)",
        "task_id": "\(taskId)",
        "key": "\(key)",
        "value": \(valueJSON),
        "previous_value": null,
        "delta_note": null,
        "checked_at": "2026-04-12T18:00:00Z",
        "created_at": "2026-04-12T18:00:00Z",
        "updated_at": "2026-04-12T18:00:00Z"
      }
    }
    """
    return Data(json.utf8)
}

private func makeTaskEnvelopeData(
    objectiveId: UUID,
    taskId: UUID,
    description: String,
    status: String,
    resultSummary: String?
) -> Data {
    let resultSummaryJSON: String = {
        guard let resultSummary else { return "null" }
        return String(
            data: try! JSONSerialization.data(withJSONObject: resultSummary, options: [.fragmentsAllowed]),
            encoding: .utf8
        )!
    }()
    let json = """
    {
      "task": {
        "id": "\(taskId.uuidString)",
        "objective_id": "\(objectiveId.uuidString)",
        "source_feedback_id": null,
        "description": "\(description)",
        "task_kind": null,
        "allowed_tool_ids": null,
        "required_capabilities": null,
        "done_when": null,
        "status": "\(status)",
        "result_summary": \(resultSummaryJSON),
        "created_at": "2026-04-12T18:00:00Z",
        "updated_at": "2026-04-12T18:00:00Z"
      }
    }
    """
    return Data(json.utf8)
}


/// Regression test for the April 2026 incident where `default-local.store`
/// became corrupted (NSSQLiteErrorDomain=1), causing all worker loops to crash
/// silently after webhook delivery. Fix: delete the store so SwiftData recreates
/// it clean. This test verifies the pool can accept a payload and create work
/// units without errors on a fresh in-memory container (equivalent to a clean store).
@Test("Fresh container after store deletion: pool creates work units without crashing")
func freshContainerAfterStoreDeletionCreatesWorkUnits() async throws {
    // Simulate a freshly recreated store by using a brand-new in-memory container.
    let (container, context) = try makeContainer()

    let pool = makePool(
        container: container,
        context: context,
        client: MockOllamaClient(responses: [.assistantFinal(content: "Research complete.")]),
        timeoutSeconds: 10
    )
    await pool.start()

    let taskId = UUID()
    let objectiveId = UUID()
    let json = taskSearchJSON(taskId: taskId, objectiveId: objectiveId, description: "Verify SEPTA API docs")
    let payload = try #require(TaskSearchPayload(json: json))
    await pool.enqueue(payload)

    // Supervisor should create at least a root WorkUnit without crashing.
    let deadline = Date().addingTimeInterval(5)
    var rootFound = false
    while Date() < deadline {
        let readContext = ModelContext(container)
        let units = try readContext.fetch(FetchDescriptor<WorkUnit>())
        if units.contains(where: { $0.objectiveId == objectiveId && $0.workType == "objective_root" }) {
            rootFound = true
            break
        }
        try await Task.sleep(for: .milliseconds(100))
    }

    #expect(rootFound, "Fresh pool should create root WorkUnit — store corruption fix regression.")
}

/// Verifies that BackendAPIClient contains no reference to `/v1/missions`,
/// confirming the old polling path was removed and will not flood the API with 404s.
@Test("BackendAPIClient source contains no v1/missions path")
func backendAPIClientHasNoMissionsPath() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()          // AgentKVTMacTests/
        .deletingLastPathComponent()          // Tests/
        .deletingLastPathComponent()          // AgentKVTMac/
        .appendingPathComponent("Sources/AgentKVTMac/BackendAPIClient.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    #expect(!source.contains("v1/missions"), "BackendAPIClient must not reference the removed /v1/missions endpoint.")
}

@Test("Startup sweep resumes orphaned objective by creating synthesis unit")
func startupSweepCreatesMissingSynthesisUnit() async throws {
    let (container, context) = try makeContainer()
    let objectiveId = UUID()
    let taskId = UUID()
    let taskDescription = "Build a family travel plan"

    let root = WorkUnit(
        title: taskDescription,
        category: "objective",
        objectiveId: objectiveId,
        sourceTaskId: taskId,
        workType: "objective_root",
        state: WorkUnitState.inProgress.rawValue
    )
    let research = WorkUnit(
        title: "Research flight options",
        category: "objective",
        objectiveId: objectiveId,
        sourceTaskId: taskId,
        workType: "objective_research",
        state: WorkUnitState.done.rawValue,
        moundPayload: try payloadData(objectiveId: objectiveId, taskId: taskId, taskDescription: taskDescription),
        activePhaseHint: "research"
    )
    context.insert(root)
    context.insert(research)
    try context.save()

    let pool = makePool(
        container: container,
        context: context,
        client: MockOllamaClient(responses: [.assistantFinal(content: "ok")]),
        timeoutSeconds: 5
    )
    await pool.start()

    let deadline = Date().addingTimeInterval(3)
    var synthesisExists = false
    while Date() < deadline {
        let readContext = ModelContext(container)
        let units = try readContext.fetch(FetchDescriptor<WorkUnit>())
        if units.contains(where: {
            $0.objectiveId == objectiveId &&
            $0.sourceTaskId == taskId &&
            $0.workType == "objective_synthesis"
        }) {
            synthesisExists = true
            break
        }
        try await Task.sleep(for: .milliseconds(100))
    }

    #expect(synthesisExists, "Expected startup sweep to create missing synthesis work unit for orphaned objective.")
}

@Test("Supervisor keeps waiting through a retryable synthesis snapshot timeout")
func supervisorRetriesTransientSynthesisSnapshotTimeout() async throws {
    let (container, context) = try makeContainer()
    let objectiveId = UUID()
    let taskId = UUID()
    let taskDescription = "Turn the current research into a family-ready summary"
    let objectiveGoal = "Turn the current research into a clear recommendation with next steps."

    let backendState = BackendStubState()
    let backendHost = "objective-execution-retry.example.test"
    ObjectiveExecutionBackendURLProtocol.setHandler(forHost: backendHost) { request in
        guard let url = request.url else {
            throw URLError(.badURL)
        }

        let okResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let createdResponse = HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)!

        switch (request.httpMethod ?? "GET", url.path) {
        case ("GET", "/v1/agent/objectives/\(objectiveId.uuidString)/research_snapshots"):
            return (okResponse, makeResearchSnapshotsEnvelopeData())

        case ("POST", "/v1/agent/logs"):
            let content = backendState.recordAgentLogContent(from: request)
            if content?.contains("Synthesis snapshot write failed:") == true {
                Thread.sleep(forTimeInterval: 3.0)
            }
            return (createdResponse, makeAgentLogEnvelopeData(request: request))

        case ("POST", "/v1/agent/objectives/\(objectiveId.uuidString)/research_snapshots"):
            let attempt = backendState.nextSynthesisSnapshotWriteAttempt()
            if attempt == 1 {
                throw URLError(.timedOut)
            }
            return (createdResponse, makeResearchSnapshotEnvelopeData(request: request, objectiveId: objectiveId))

        default:
            return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
    }
    defer { ObjectiveExecutionBackendURLProtocol.reset(host: backendHost) }

    let backendClient = BackendAPIClient(
        baseURL: URL(string: "https://\(backendHost)")!,
        workspaceSlug: "test-workspace",
        agentToken: "test-agent-token",
        session: ObjectiveExecutionBackendURLProtocol.makeSession()
    )

    let root = WorkUnit(
        title: taskDescription,
        category: "objective",
        objectiveId: objectiveId,
        sourceTaskId: taskId,
        workType: "objective_root",
        state: WorkUnitState.inProgress.rawValue,
        activePhaseHint: "timed_out"
    )
    context.insert(root)
    try context.save()

    let pool = makePool(
        container: container,
        context: context,
        client: MockOllamaClient(responses: [
            .assistantFinal(content: "Here is the synthesized summary and the strongest next step.")
        ]),
        backendClient: backendClient,
        timeoutSeconds: 5
    )

    let payload = try #require(TaskSearchPayload(json: taskSearchJSON(
        taskId: taskId,
        objectiveId: objectiveId,
        description: taskDescription,
        objectiveGoal: objectiveGoal
    )))
    await pool.enqueue(payload)

    let deadline = Date().addingTimeInterval(15)
    var rootFinished = false
    while Date() < deadline {
        let readContext = ModelContext(container)
        let units = try readContext.fetch(FetchDescriptor<WorkUnit>())
        if units.first(where: { $0.id == root.id })?.state == WorkUnitState.done.rawValue {
            rootFinished = true
            break
        }
        try await Task.sleep(for: .milliseconds(200))
    }

    let logContents = backendState.agentLogContentsSnapshot()
    #expect(rootFinished, "Expected the supervisor to keep waiting through a retryable synthesis timeout and finish the root work unit.")
    #expect(
        backendState.synthesisSnapshotWriteAttemptsSnapshot() >= 2,
        "Expected the synthesis snapshot write to retry after the first timeout."
    )
    #expect(
        !logContents.contains(where: { $0.contains("Objective supervisor failed") }),
        "Supervisor should not emit a terminal failure log for a retryable synthesis timeout."
    )
}

@Test("Supervisor failure marks the backend task failed instead of leaving it stuck in progress")
func supervisorFailureTransitionsBackendTaskOutOfInProgress() async throws {
    let (container, context) = try makeContainer()
    let objectiveId = UUID()
    let taskId = UUID()
    let taskDescription = "Turn the current research into a family-ready summary"
    let objectiveGoal = "Turn the current research into a recommendation with the best next move."

    let backendState = BackendStubState()
    let backendHost = "objective-execution-failure.example.test"
    ObjectiveExecutionBackendURLProtocol.setHandler(forHost: backendHost) { request in
        guard let url = request.url else {
            throw URLError(.badURL)
        }

        let okResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let createdResponse = HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)!

        switch (request.httpMethod ?? "GET", url.path) {
        case ("GET", "/v1/agent/objectives/\(objectiveId.uuidString)/research_snapshots"):
            return (okResponse, makeResearchSnapshotsEnvelopeData())

        case ("POST", "/v1/agent/logs"):
            _ = backendState.recordAgentLogContent(from: request)
            return (createdResponse, makeAgentLogEnvelopeData(request: request))

        case ("POST", "/v1/agent/objectives/\(objectiveId.uuidString)/tasks/\(taskId.uuidString)/fail"):
            let message = backendState.recordFailedTaskMessage(from: request) ?? "unknown error"
            return (
                okResponse,
                makeTaskEnvelopeData(
                    objectiveId: objectiveId,
                    taskId: taskId,
                    description: taskDescription,
                    status: "failed",
                    resultSummary: message
                )
            )

        default:
            return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
    }
    defer { ObjectiveExecutionBackendURLProtocol.reset(host: backendHost) }

    let backendClient = BackendAPIClient(
        baseURL: URL(string: "https://\(backendHost)")!,
        workspaceSlug: "test-workspace",
        agentToken: "test-agent-token",
        session: ObjectiveExecutionBackendURLProtocol.makeSession()
    )

    let pool = makePool(
        container: container,
        context: context,
        client: MockOllamaClient(responses: [
            // The objective board runner retries once when the model writes raw tool-call JSON as text.
            .assistantFinal(content: #"{"tool_calls":[{"name":"write_objective_snapshot","arguments":{"mark_task_completed":true}}]}"#),
            .assistantFinal(content: #"{"tool_calls":[{"name":"write_objective_snapshot","arguments":{"mark_task_completed":true}}]}"#)
        ]),
        backendClient: backendClient,
        timeoutSeconds: 5
    )

    let payload = try #require(TaskSearchPayload(json: taskSearchJSON(
        taskId: taskId,
        objectiveId: objectiveId,
        description: taskDescription,
        objectiveGoal: objectiveGoal
    )))
    await pool.enqueue(payload)

    let deadline = Date().addingTimeInterval(10)
    var rootBlocked = false
    var backendTaskFailed = false
    while Date() < deadline {
        let readContext = ModelContext(container)
        let units = try readContext.fetch(FetchDescriptor<WorkUnit>())
        if units.first(where: { $0.objectiveId == objectiveId && $0.sourceTaskId == taskId && $0.workType == "objective_root" })?.state == WorkUnitState.blocked.rawValue {
            rootBlocked = true
        }
        backendTaskFailed = backendState.failedTaskMessagesSnapshot().contains(where: {
            $0.contains("Model returned JSON instead of a final prose summary")
        })
        if rootBlocked && backendTaskFailed {
            break
        }
        try await Task.sleep(for: .milliseconds(200))
    }

    #expect(rootBlocked, "Expected supervisor failure to mark the root work unit blocked locally.")
    #expect(
        backendTaskFailed,
        "Expected the supervisor failure path to transition the backend task out of in_progress with the synthesis error."
    )
}
