import Foundation

/// Protocol for LLM chat (enables mocking in integration tests).
public protocol OllamaClientProtocol: Sendable {
    func chat(messages: [OllamaClient.Message], tools: [OllamaClient.ToolDef]?) async throws -> OllamaClient.Message
    /// Returns true if the backend is reachable and can respond quickly.
    /// Used as a pre-flight check before claiming a work unit to avoid the
    /// claim-then-timeout loop. Defaults to true for mock/test conformers.
    func isHealthy() async -> Bool
}

public extension OllamaClientProtocol {
    func isHealthy() async -> Bool { true }
}

/// HTTP client for Ollama chat API with tool-calling support.
/// See https://github.com/ollama/ollama/blob/main/docs/api.md
///
/// Operational config: On a dedicated machine (e.g. Mac Studio), configure the LLM host for up to 90%
/// memory/GPU utilization; see Docs/LLM_THROTTLING.md.
public final class OllamaClient: @unchecked Sendable {
    public let baseURL: URL
    public let model: String
    public let timeoutInterval: TimeInterval
    private let session: URLSession

    public init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        model: String = "qwen3.6:35b",
        timeoutInterval: TimeInterval = 300,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.model = model
        self.timeoutInterval = timeoutInterval
        self.session = session
    }

    /// One message in a chat.
    public struct Message: Codable, Sendable {
        public let role: String
        public let content: String?
        public let toolCalls: [ToolCall]?
        /// When role == "tool", name of the tool that produced this result (Ollama may expect tool_name).
        public let name: String?

        public init(role: String, content: String?, toolCalls: [ToolCall]? = nil, name: String? = nil) {
            self.role = role
            self.content = content
            self.toolCalls = toolCalls
            self.name = name
        }

        enum CodingKeys: String, CodingKey {
            case role, content, name
            case toolCalls = "tool_calls"
            case toolName = "tool_name"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            role = try c.decode(String.self, forKey: .role)
            content = try c.decodeIfPresent(String.self, forKey: .content)
            toolCalls = try c.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? c.decodeIfPresent(String.self, forKey: .toolName)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(role, forKey: .role)
            try c.encodeIfPresent(content, forKey: .content)
            try c.encodeIfPresent(toolCalls, forKey: .toolCalls)
            if role == "tool", let n = name { try c.encode(n, forKey: .toolName) }
        }
    }

    /// Tool call from the model.
    public struct ToolCall: Codable, Sendable {
        public let id: String?
        public let type: String?
        public let function: FunctionCall?

        public init(id: String?, type: String?, function: FunctionCall?) {
            self.id = id
            self.type = type
            self.function = function
        }

        public struct FunctionCall: Codable, Sendable {
            public let name: String
            public let arguments: String

            enum CodingKeys: String, CodingKey {
                case name, arguments
            }

            public init(name: String, arguments: String) {
                self.name = name
                self.arguments = arguments
            }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decode(String.self, forKey: .name)
                if let stringValue = try? c.decode(String.self, forKey: .arguments) {
                    arguments = stringValue
                } else {
                    let jsonValue = try c.decode(JSONValue.self, forKey: .arguments)
                    arguments = try jsonValue.jsonString()
                }
            }

            public func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(name, forKey: .name)
                try c.encode(arguments, forKey: .arguments)
            }
        }
        enum CodingKeys: String, CodingKey {
            case id, type, function
        }
    }

    /// Tool definition for the API (Ollama format).
    public struct ToolDef: Encodable, Sendable {
        public let function: FunctionDef

        public init(function: FunctionDef) {
            self.function = function
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode("function", forKey: .type)
            try c.encode(function, forKey: .function)
        }
        private enum CodingKeys: String, CodingKey { case type, function }

        public struct FunctionDef: Codable, Sendable {
            public let name: String
            public let description: String?
            public let parameters: JSONSchema?

            public init(name: String, description: String?, parameters: JSONSchema?) {
                self.name = name
                self.description = description
                self.parameters = parameters
            }
        }

        public struct JSONSchema: Codable, Sendable {
            public let type: String
            public let properties: [String: Property]?
            public let required: [String]?

            public init(type: String, properties: [String: Property]?, required: [String]?) {
                self.type = type
                self.properties = properties
                self.required = required
            }

            public struct Property: Codable, Sendable {
                public let type: String
                public let description: String?
                public let enumValues: [String]?

                public init(type: String, description: String?, enumValues: [String]? = nil) {
                    self.type = type
                    self.description = description
                    self.enumValues = enumValues
                }

                private enum CodingKeys: String, CodingKey {
                    case type
                    case description
                    case enumValues = "enum"
                }
            }
        }
    }

    /// Request body for /api/chat.
    struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let tools: [ToolDef]?
        let stream: Bool
        let options: ChatOptions?
    }

    struct ChatOptions: Encodable {
        let temperature: Double
    }

    /// Response from /api/chat (non-streaming).
    public struct ChatResponse: Decodable {
        public let message: Message?
        public let done: Bool?
        public let error: String?
        /// Number of tokens in the prompt (Ollama: prompt_eval_count).
        public let promptEvalCount: Int?
        /// Number of tokens generated (Ollama: eval_count).
        public let evalCount: Int?

        enum CodingKeys: String, CodingKey {
            case message, done, error
            case promptEvalCount = "prompt_eval_count"
            case evalCount = "eval_count"
        }
    }

    private struct ManualToolResponse: Decodable {
        let content: String?
        let toolCalls: [ManualToolCall]?

        enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
        }

        struct ManualToolCall: Decodable {
            let name: String
            let arguments: JSONValue
        }
    }

    /// Send chat request and return the assistant message (and optional tool_calls).
    public func chat(messages: [Message], tools: [ToolDef]? = nil) async throws -> Message {
        do {
            return try await performChat(messages: messages, tools: tools)
        } catch let OllamaError.apiError(message)
            where (tools?.isEmpty == false) && shouldRetryWithManualToolMode(apiErrorMessage: message) {
            return try await performManualToolChat(messages: messages, tools: tools ?? [])
        }
    }

    private func performChat(messages: [Message], tools: [ToolDef]?) async throws -> Message {
        let url = baseURL.appending(path: "api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // timeoutInterval is the per-chunk inactivity timeout in streaming mode —
        // the overall request won't timeout as long as the model keeps producing tokens.
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: model,
                messages: messages,
                tools: tools,
                stream: true,
                options: ChatOptions(temperature: 0)
            )
        )

        let requestStart = Date()
        let (asyncBytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw OllamaError.invalidResponse }
        guard http.statusCode == 200 else {
            var errorData = Data()
            for try await byte in asyncBytes { errorData.append(byte) }
            if let err = try? JSONDecoder().decode(ChatResponse.self, from: errorData).error { throw OllamaError.apiError(err) }
            throw OllamaError.httpStatus(http.statusCode)
        }

        var accumulatedContent = ""
        var accumulatedToolCalls: [ToolCall] = []
        var promptEvalCount: Int?
        var evalCount: Int?

        for try await line in asyncBytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            guard let chunk = try? JSONDecoder().decode(ChatResponse.self, from: data) else { continue }
            if let content = chunk.message?.content { accumulatedContent += content }
            if let calls = chunk.message?.toolCalls { accumulatedToolCalls += calls }
            if chunk.done == true {
                promptEvalCount = chunk.promptEvalCount
                evalCount = chunk.evalCount
            }
        }

        let latencyMs = Int(Date().timeIntervalSince(requestStart) * 1000)
        if let input = promptEvalCount, let output = evalCount {
            Task { await TokenUsageLogger.shared.record(model: model, promptTokens: input, completionTokens: output, latencyMs: latencyMs) }
        }

        let msg = Message(
            role: "assistant",
            content: accumulatedContent.isEmpty ? nil : accumulatedContent,
            toolCalls: accumulatedToolCalls.isEmpty ? nil : accumulatedToolCalls
        )
        return coerceAssistantMessageIfNeeded(msg, tools: tools)
    }

    /// When tools are enabled, some models return HTTP 200 with `tool_calls` serialized inside `content` instead of structured fields.
    private func coerceAssistantMessageIfNeeded(_ msg: Message, tools: [ToolDef]?) -> Message {
        guard let tools, !tools.isEmpty else { return msg }
        if let tc = msg.toolCalls, !tc.isEmpty { return msg }
        let rawContent = msg.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawContent.isEmpty else { return msg }
        let normalized = normalizeManualToolPayload(rawContent)
        guard let data = normalized.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(ManualToolResponse.self, from: data),
              let toolCalls = parsed.toolCalls, !toolCalls.isEmpty
        else { return msg }
        do {
            let mapped = try toolCalls.map { call in
                ToolCall(
                    id: nil,
                    type: "function",
                    function: .init(name: call.name, arguments: try call.arguments.jsonString())
                )
            }
            return .init(role: "assistant", content: parsed.content, toolCalls: mapped)
        } catch {
            return msg
        }
    }

    private func performManualToolChat(messages: [Message], tools: [ToolDef]) async throws -> Message {
        let manualMessages = ManualToolMode.makeMessages(from: messages, tools: tools)
        let raw = try await performChat(messages: manualMessages, tools: nil)
        let rawContent = raw.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ManualToolMode.parseResponse(rawContent)
    }

    private func shouldRetryWithManualToolMode(apiErrorMessage: String) -> Bool {
        let lowercased = apiErrorMessage.lowercased()
        return lowercased.contains("value looks like object")
            || lowercased.contains("tool")
            || lowercased.contains("closing '}'")
    }

    private func makeManualToolMessages(from messages: [Message], tools: [ToolDef]) -> [Message] {
        let toolDescriptions = tools.map { tool in
            let params = (try? JSONEncoder().encode(tool.function.parameters))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "null"
            return "- \(tool.function.name): \(tool.function.description ?? "No description"). Parameters schema: \(params)"
        }.joined(separator: "\n")

        let manualToolSystemPrompt = """
        Automatic tool calling is unavailable for this request.
        You must respond with JSON only, no Markdown and no prose outside JSON.

        If you need to call a tool, respond exactly like:
        {"tool_calls":[{"name":"tool_name","arguments":{"key":"value"}}]}

        If you want to answer normally without a tool, respond exactly like:
        {"content":"your reply"}

        Available tools:
        \(toolDescriptions)
        """

        var manualMessages: [Message] = [
            .init(role: "system", content: manualToolSystemPrompt, toolCalls: nil)
        ]

        for message in messages {
            switch message.role {
            case "tool":
                let toolName = message.name ?? "tool"
                manualMessages.append(
                    .init(
                        role: "user",
                        content: "Tool result from \(toolName):\n\(message.content ?? "")",
                        toolCalls: nil
                    )
                )
            case "assistant":
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    let summary = toolCalls.compactMap { call -> String? in
                        guard let function = call.function else { return nil }
                        return "Requested tool \(function.name) with arguments \(function.arguments)"
                    }.joined(separator: "\n")
                    manualMessages.append(.init(role: "assistant", content: summary, toolCalls: nil))
                } else {
                    manualMessages.append(.init(role: message.role, content: message.content, toolCalls: nil))
                }
            default:
                manualMessages.append(.init(role: message.role, content: message.content, toolCalls: nil))
            }
        }

        return manualMessages
    }

    private func normalizeManualToolPayload(_ rawContent: String) -> String {
        // Strip <think>...</think> blocks (qwen3 thinking-mode output)
        let noThink = Self.stripXMLBlocks(tag: "think", from: rawContent)
        let trimmed = noThink.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip ``` code fences
        if trimmed.hasPrefix("```") {
            let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            guard lines.count >= 3 else { return trimmed }
            let body = lines.dropFirst().dropLast().joined(separator: "\n")
            return String(body).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Extract <tool_call>...</tool_call> blocks (qwen3 native format) and reformat
        // as ManualToolResponse JSON: {"tool_calls": [...]}
        let toolCallBlocks = Self.extractXMLBlocks(tag: "tool_call", from: trimmed)
        if !toolCallBlocks.isEmpty {
            let joined = toolCallBlocks
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: ",")
            return "{\"tool_calls\":[\(joined)]}"
        }

        // Single JSON object {"name": "...", "arguments": {...}} — wrap in tool_calls array
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           obj["name"] is String, obj["arguments"] != nil, obj["tool_calls"] == nil {
            return "{\"tool_calls\":[\(trimmed)]}"
        }

        return trimmed
    }

    private static func stripXMLBlocks(tag: String, from content: String) -> String {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        var result = content
        while let startRange = result.range(of: open),
              let endRange = result.range(of: close, range: startRange.upperBound..<result.endIndex) {
            result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        }
        return result
    }

    private static func extractXMLBlocks(tag: String, from content: String) -> [String] {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        var blocks: [String] = []
        var searchRange = content.startIndex..<content.endIndex
        while let startRange = content.range(of: open, range: searchRange),
              let endRange = content.range(of: close, range: startRange.upperBound..<content.endIndex) {
            blocks.append(String(content[startRange.upperBound..<endRange.lowerBound]))
            searchRange = endRange.upperBound..<content.endIndex
        }
        return blocks
    }
}

extension OllamaClient: OllamaClientProtocol {
    public func isHealthy() async -> Bool {
        let url = baseURL.appending(path: "/api/tags")
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

public enum OllamaError: Error {
    case invalidResponse
    case httpStatus(Int)
    case apiError(String)
    case noMessage
}

enum JSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
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

    func jsonString() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(self, .init(codingPath: [], debugDescription: "Unable to encode JSON value as UTF-8 string."))
        }
        return string
    }
}
