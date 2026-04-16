import Foundation

/// Tool that executes up to 5 sequential search or browse sub-queries and returns a
/// synthesized Markdown document. Calls the existing WebSearchTool and
/// HeadlessBrowserScout static helpers directly — no nested AgentLoop.
public func makeMultiStepSearchTool(apiKey: String? = nil) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "multi_step_search",
        name: "multi_step_search",
        description: """
            Run 2–5 related search or browse sub-queries in a single turn and receive one synthesized Markdown report.
            Use for comparison research (e.g. check hotel prices across multiple sites, compare flight options).
            Each step is either a web search ("search") or a direct URL browse ("browse").
            Results are capped per step to preserve context. Review the report before taking further action.
            """,
        parameters: .init(
            type: "object",
            properties: [
                "steps_json": .init(
                    type: "string",
                    description: """
                        JSON array of up to 5 step objects. Each step must have:
                        - "type": "search" or "browse"
                        - "query": search query string (required when type == "search")
                        - "url": full URL to load (required when type == "browse")
                        - "actions_json": optional JSON array of browser actions (only used with "browse")
                        Example: [{"type":"search","query":"Loews Royal Pacific hotel rates July 2025"},{"type":"browse","url":"https://www.loewshotels.com/royal-pacific-resort"}]
                        """
                )
            ],
            required: ["steps_json"]
        ),
        handler: { args in
            guard let stepsJson = args["steps_json"] as? String else {
                return "Error: steps_json is required."
            }
            guard let rawSteps = parseStepObjects(from: stepsJson), !rawSteps.isEmpty else {
                return "Error: steps_json must be a JSON array of step objects (type/query/url). Strip markdown fences if present."
            }

            let steps = Array(rawSteps.prefix(5))
            guard !steps.isEmpty else {
                return "Error: steps_json must contain at least one step."
            }

            let truncatedNote = rawSteps.count > 5
                ? "\n\n> Note: \(rawSteps.count - 5) step(s) were dropped (maximum is 5)."
                : ""

            var sections: [String] = []

            for (i, step) in steps.enumerated() {
                let stepNum = i + 1
                let type = step["type"]?.lowercased() ?? ""
                let result: String

                switch type {
                case "search":
                    guard let query = step["query"], !query.isEmpty else {
                        sections.append("### Step \(stepNum): search\n\nError: missing or empty query.")
                        continue
                    }
                    result = await WebSearchTool.searchAndFetch(
                        query: query,
                        maxResults: 3,
                        apiKeyOverride: apiKey
                    )
                    let capped = cap(result, chars: 6000)
                    sections.append("### Step \(stepNum): search — \(query)\n\n\(capped)")

                case "browse":
                    guard let url = step["url"], !url.isEmpty else {
                        sections.append("### Step \(stepNum): browse\n\nError: missing or empty url.")
                        continue
                    }
                    result = await HeadlessBrowserScout.run(url: url, actionsJson: step["actions_json"])
                    let capped = cap(result, chars: 6000)
                    sections.append("### Step \(stepNum): browse — \(url)\n\n\(capped)")

                default:
                    sections.append("### Step \(stepNum): unknown type '\(type)'\n\nError: type must be 'search' or 'browse'.")
                }
            }

            return sections.joined(separator: "\n\n---\n\n") + truncatedNote
        }
    )
}

private func cap(_ string: String, chars: Int) -> String {
    guard string.count > chars else { return string }
    return String(string.prefix(chars)) + "\n\n[Truncated for context.]"
}

/// Strips ```json fences and parses a JSON array of objects into string dictionaries (values coerced to strings).
/// Also handles the double-nested pattern the LLM sometimes emits:
///   {"steps_json": "[{...}]"}  or  {"steps_json": {"steps_json": "[{...}]"}}
private func parseStepObjects(from stepsJson: String) -> [[String: String]]? {
    let stripped = stripMarkdownCodeFences(stepsJson.trimmingCharacters(in: .whitespacesAndNewlines))
    guard let data = stripped.data(using: .utf8) else { return nil }
    guard let top = try? JSONSerialization.jsonObject(with: data) else { return nil }
    return extractStepObjects(from: top, depth: 0)
}

private func extractStepObjects(from value: Any, depth: Int) -> [[String: String]]? {
    guard depth < 4 else { return nil }
    if let arr = value as? [[String: Any]] {
        return arr.map(stringifyStepDictionary)
    }
    if let dict = value as? [String: Any] {
        // Unwrap {"steps_json": "..."} or {"steps_json": [...]} recursively
        if let inner = dict["steps_json"] {
            if let innerString = inner as? String {
                let stripped = stripMarkdownCodeFences(innerString.trimmingCharacters(in: .whitespacesAndNewlines))
                if let data = stripped.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) {
                    return extractStepObjects(from: parsed, depth: depth + 1)
                }
            } else {
                return extractStepObjects(from: inner, depth: depth + 1)
            }
        }
        // Single-step object passed directly
        return [stringifyStepDictionary(dict)]
    }
    return nil
}

private func stripMarkdownCodeFences(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```") else { return trimmed }
    let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count >= 3 else { return trimmed }
    return lines.dropFirst().dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

private func stringifyStepDictionary(_ dict: [String: Any]) -> [String: String] {
    var out: [String: String] = [:]
    for (key, value) in dict {
        switch value {
        case let str as String:
            out[key] = str
        case let num as NSNumber:
            out[key] = num.stringValue
        case let bool as Bool:
            out[key] = bool ? "true" : "false"
        case let sub as [String: Any]:
            if let d = try? JSONSerialization.data(withJSONObject: sub),
               let s = String(data: d, encoding: .utf8) {
                out[key] = s
            }
        case let sub as [Any]:
            if let d = try? JSONSerialization.data(withJSONObject: sub),
               let s = String(data: d, encoding: .utf8) {
                out[key] = s
            }
        default:
            break
        }
    }
    return out
}
