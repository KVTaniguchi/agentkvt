import Foundation

/// Shared utilities for manual tool-call mode — used when Ollama's tool API returns an error
/// and the call must be retried with a JSON-prompt-based tool-calling approach.
///
/// Protocol: the model is given a JSON-only system prompt describing the tools, and
/// must respond with either {"tool_calls":[...]} or {"content":"..."}.
public enum ManualToolMode {

    // MARK: - Message construction

    /// Wraps messages with a manual tool-calling system prompt that instructs the model
    /// to respond in JSON with tool_calls or content — no native tool API needed.
    public static func makeMessages(
        from messages: [OllamaClient.Message],
        tools: [OllamaClient.ToolDef]
    ) -> [OllamaClient.Message] {
        let toolDescriptions = tools.map { tool in
            let params = (try? JSONEncoder().encode(tool.function.parameters))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "null"
            return "- \(tool.function.name): \(tool.function.description ?? "No description"). Parameters schema: \(params)"
        }.joined(separator: "\n")

        let systemPrompt = """
        You have access to tools. You MUST use them to complete the task — do not answer from memory alone.
        Respond with JSON only, no Markdown and no prose outside JSON.

        To call a tool, respond exactly like:
        {"tool_calls":[{"name":"tool_name","arguments":{"key":"value"}}]}

        To give a final answer without calling a tool, respond exactly like:
        {"content":"your reply"}

        Available tools:
        \(toolDescriptions)
        """

        var result: [OllamaClient.Message] = [
            .init(role: "system", content: systemPrompt, toolCalls: nil)
        ]

        for message in messages {
            switch message.role {
            case "tool":
                let toolName = message.name ?? "tool"
                result.append(.init(
                    role: "user",
                    content: "Tool result from \(toolName):\n\(message.content ?? "")",
                    toolCalls: nil
                ))
            case "assistant":
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    let summary = toolCalls.compactMap { call -> String? in
                        guard let function = call.function else { return nil }
                        return "Requested tool \(function.name) with arguments \(function.arguments)"
                    }.joined(separator: "\n")
                    result.append(.init(role: "assistant", content: summary, toolCalls: nil))
                } else {
                    result.append(.init(role: message.role, content: message.content, toolCalls: nil))
                }
            default:
                result.append(.init(role: message.role, content: message.content, toolCalls: nil))
            }
        }

        return result
    }

    // MARK: - Response parsing

    /// Parses a raw string response from a model in manual tool mode into an OllamaClient.Message,
    /// populating toolCalls when the model responded with {"tool_calls":[...]}.
    public static func parseResponse(_ raw: String) -> OllamaClient.Message {
        let normalized = normalize(raw)
        guard let data = normalized.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(ManualToolResponse.self, from: data)
        else {
            return .init(role: "assistant", content: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let toolCalls = try? parsed.toolCalls?.map { call in
            OllamaClient.ToolCall(
                id: nil,
                type: "function",
                function: .init(name: call.name, arguments: try call.arguments.jsonString())
            )
        }
        return .init(role: "assistant", content: parsed.content, toolCalls: toolCalls)
    }

    // MARK: - Normalization

    public static func normalize(_ rawContent: String) -> String {
        let noThink = stripXMLBlocks(tag: "think", from: rawContent)
        let trimmed = noThink.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("```") {
            let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            guard lines.count >= 3 else { return trimmed }
            return String(lines.dropFirst().dropLast().joined(separator: "\n"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let toolCallBlocks = extractXMLBlocks(tag: "tool_call", from: trimmed)
        if !toolCallBlocks.isEmpty {
            let joined = toolCallBlocks
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: ",")
            return "{\"tool_calls\":[\(joined)]}"
        }

        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           obj["name"] is String, obj["arguments"] != nil, obj["tool_calls"] == nil {
            return "{\"tool_calls\":[\(trimmed)]}"
        }

        return trimmed
    }

    // MARK: - XML helpers

    public static func stripXMLBlocks(tag: String, from content: String) -> String {
        let open = "<\(tag)>"; let close = "</\(tag)>"
        var result = content
        while let s = result.range(of: open),
              let e = result.range(of: close, range: s.upperBound..<result.endIndex) {
            result.removeSubrange(s.lowerBound..<e.upperBound)
        }
        return result
    }

    public static func extractXMLBlocks(tag: String, from content: String) -> [String] {
        let open = "<\(tag)>"; let close = "</\(tag)>"
        var blocks: [String] = []
        var search = content.startIndex..<content.endIndex
        while let s = content.range(of: open, range: search),
              let e = content.range(of: close, range: s.upperBound..<content.endIndex) {
            blocks.append(String(content[s.upperBound..<e.lowerBound]))
            search = e.upperBound..<content.endIndex
        }
        return blocks
    }
}

// MARK: - Internal response shape

struct ManualToolResponse: Decodable {
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
