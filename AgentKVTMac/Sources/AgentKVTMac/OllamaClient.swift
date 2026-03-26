import Foundation

/// Protocol for LLM chat (enables mocking in integration tests).
public protocol OllamaClientProtocol {
    func chat(messages: [OllamaClient.Message], tools: [OllamaClient.ToolDef]?) async throws -> OllamaClient.Message
}

/// HTTP client for Ollama chat API with tool-calling support.
/// See https://github.com/ollama/ollama/blob/main/docs/api.md
///
/// Operational config: On a dedicated machine (e.g. Mac Studio), configure the LLM host for up to 90%
/// memory/GPU utilization; see Docs/LLM_THROTTLING.md.
public final class OllamaClient: @unchecked Sendable {
    public let baseURL: URL
    public let model: String
    private let session: URLSession

    public init(baseURL: URL = URL(string: "http://localhost:11434")!, model: String = "llama3.2", session: URLSession = .shared) {
        self.baseURL = baseURL
        self.model = model
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
        }

        public struct JSONSchema: Codable, Sendable {
            public let type: String
            public let properties: [String: Property]?
            public let required: [String]?

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
    }

    /// Response from /api/chat (non-streaming).
    public struct ChatResponse: Decodable {
        public let message: Message?
        public let done: Bool?
        public let error: String?
    }

    /// Send chat request and return the assistant message (and optional tool_calls).
    public func chat(messages: [Message], tools: [ToolDef]? = nil) async throws -> Message {
        let url = baseURL.appending(path: "api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ChatRequest(model: model, messages: messages, tools: tools, stream: false))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OllamaError.invalidResponse }
        guard http.statusCode == 200 else {
            if let err = try? JSONDecoder().decode(ChatResponse.self, from: data).error { throw OllamaError.apiError(err) }
            throw OllamaError.httpStatus(http.statusCode)
        }
        let parsed = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let msg = parsed.message else { throw OllamaError.noMessage }
        return msg
    }
}

extension OllamaClient: OllamaClientProtocol {}

public enum OllamaError: Error {
    case invalidResponse
    case httpStatus(Int)
    case apiError(String)
    case noMessage
}

private enum JSONValue: Codable, Sendable {
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
