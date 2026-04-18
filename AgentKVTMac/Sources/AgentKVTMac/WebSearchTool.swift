import Foundation

/// Web Scout Tool: integrates with Ollama's web search and web fetch APIs to retrieve
/// up-to-date information. Strips ads, footers, and scripts and returns clean Markdown
/// to save 80–90% of the LLM context window.
///
/// Requires OLLAMA_API_KEY (from https://ollama.com/settings/keys).
/// APIs: https://ollama.com/api/web_search, https://ollama.com/api/web_fetch
public func makeWebSearchAndFetchTool(apiKey: String? = nil) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "web_search_and_fetch",
        name: "web_search_and_fetch",
        description: """
            Search the web for up-to-date information and fetch full page content as clean Markdown.
            Use when the mission needs current facts from the web (schedules, directions, news, product pages, etc.).
            Returns combined Markdown from search results; ads, footers, and scripts are stripped to save context.
            """,
        parameters: .init(
            type: "object",
            properties: [
                "query": .init(type: "string", description: "Web search query: derive the exact string from the mission prompt and any life context—do not substitute unrelated example text."),
                "max_results": .init(type: "string", description: "Optional. Max pages to fetch (default 3, max 5). Pass as string e.g. '3'.")
            ],
            required: ["query"]
        ),
        handler: { args in
            guard let query = args["query"] as? String, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "Error: query is required and must be non-empty."
            }
            let maxResults = (args["max_results"] as? String).flatMap(Int.init).map { min(max($0, 1), 5) } ?? 3
            return await WebSearchTool.searchAndFetch(
                query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                maxResults: maxResults,
                apiKeyOverride: apiKey
            )
        }
    )
}

enum WebSearchTool {
    private static let webSearchURL = URL(string: "https://ollama.com/api/web_search")!
    private static let webFetchURL = URL(string: "https://ollama.com/api/web_fetch")!

    /// Run web_search, then web_fetch for each result URL; return combined clean Markdown.
    static func searchAndFetch(query: String, maxResults: Int, apiKeyOverride: String? = nil) async -> String {
        guard let apiKey = resolvedAPIKey(apiKeyOverride: apiKeyOverride) else {
            return "Error: OLLAMA_API_KEY must be set for web search. Get a key at https://ollama.com/settings/keys"
        }

        var request = URLRequest(url: webSearchURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let searchBody = ["query": query, "max_results": maxResults] as [String: Any]
        request.httpBody = try? JSONSerialization.data(withJSONObject: searchBody)

        let session = URLSession.shared
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else {
            return "Error: web search request failed (network or encoding)."
        }
        guard http.statusCode == 200 else {
            let errMsg = (try? JSONDecoder().decode(WebSearchErrorResponse.self, from: data))?.error ?? "HTTP \(http.statusCode)"
            return "Error: web search failed: \(errMsg)"
        }

        let searchResponse: WebSearchResponse
        do {
            searchResponse = try JSONDecoder().decode(WebSearchResponse.self, from: data)
        } catch {
            return "Error: failed to decode web search response: \(error.localizedDescription)"
        }

        let results = Array(searchResponse.results.prefix(maxResults))
        if results.isEmpty {
            return "No search results for: \(query)"
        }

        var combined: [String] = []
        for (i, result) in results.enumerated() {
            let fetched = await fetchPage(url: result.url, apiKey: apiKey, title: result.title)
            let cleaned = cleanContent(fetched)
            combined.append("## [\(i + 1)] \(result.title)\nURL: \(result.url)\n\n\(cleaned)")
        }

        return combined.joined(separator: "\n\n---\n\n")
    }

    /// Directly fetch one URL via Ollama web_fetch and return cleaned page content.
    /// This keeps `multi_step_search` browse steps off the AppKit/WebKit path.
    static func browseAndFetch(
        url: String,
        apiKeyOverride: String? = nil,
        actionsJson: String? = nil,
        extractSelector: String? = nil
    ) async -> String {
        guard let parsed = URL(string: url), parsed.scheme == "https" || parsed.scheme == "http" else {
            return "Error: invalid or unsupported URL (must be http/https)."
        }
        guard let apiKey = resolvedAPIKey(apiKeyOverride: apiKeyOverride) else {
            return "Error: OLLAMA_API_KEY must be set for direct URL fetch. Get a key at https://ollama.com/settings/keys"
        }

        let fetched = await fetchPage(url: parsed.absoluteString, apiKey: apiKey, title: parsed.absoluteString)
        let cleaned = cleanContent(fetched)
        let note = directBrowseNote(actionsJson: actionsJson, extractSelector: extractSelector)
        guard !note.isEmpty else { return cleaned }
        return "\(note)\n\n\(cleaned)"
    }

    /// Fetch one URL via Ollama web_fetch; returns content (Markdown or HTML).
    private static func fetchPage(url: String, apiKey: String, title: String) async -> String {
        var request = URLRequest(url: webFetchURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["url": url])

        let session = URLSession.shared
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return "[Fetch failed for \(url)]"
        }

        let fetchResponse: WebFetchResponse
        do {
            fetchResponse = try JSONDecoder().decode(WebFetchResponse.self, from: data)
        } catch {
            return "[Decode error for \(url)]"
        }

        let content = fetchResponse.content ?? ""
        if content.isEmpty {
            return "Title: \(fetchResponse.title ?? title)\n(No content returned.)"
        }
        return content
    }

    private static func resolvedAPIKey(apiKeyOverride: String?) -> String? {
        let resolvedOverride = apiKeyOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let environmentAPIKey = ProcessInfo.processInfo.environment["OLLAMA_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [resolvedOverride, environmentAPIKey].compactMap { $0 }.first(where: { !$0.isEmpty })
    }

    private static func directBrowseNote(actionsJson: String?, extractSelector: String?) -> String {
        var notes: [String] = []
        if let actionsJson, !actionsJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes.append("Note: multi_step_search browse performs a direct fetch and does not execute browser actions.")
        }
        if let extractSelector, !extractSelector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes.append("Note: multi_step_search browse returns fetched page content and does not apply extract_selector.")
        }
        return notes.joined(separator: "\n")
    }

    /// Strip ads, footers, scripts; normalize whitespace; cap length to save context.
    private static func cleanContent(_ raw: String) -> String {
        var s = raw

        // If we got HTML, strip script/style/nav/footer and reduce tags to text
        if s.contains("<script") || s.contains("<style") || s.contains("<nav") || s.contains("<footer") {
            s = stripHtmlToText(s)
        }

        // Collapse excessive newlines and trim
        let lines = s.components(separatedBy: .newlines)
        var out: [String] = []
        var prevBlank = false
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                if !prevBlank { out.append("") }
                prevBlank = true
            } else {
                out.append(t)
                prevBlank = false
            }
        }

        s = out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        // Cap length to save ~80–90% context (e.g. ~12k chars per page)
        let maxChars = 14_000
        if s.count > maxChars {
            s = String(s.prefix(maxChars)) + "\n\n[Content truncated for context.]"
        }
        return s
    }

    /// Remove script/style/nav/footer and convert block tags to newlines for readability.
    private static func stripHtmlToText(_ html: String) -> String {
        var s = html
        // Remove script and style blocks (including content)
        let scriptPattern = "<script[^>]*>[\\s\\S]*?</script>"
        let stylePattern = "<style[^>]*>[\\s\\S]*?</style>"
        for pattern in [scriptPattern, stylePattern] {
            s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        // Remove nav and footer blocks
        let navPattern = "<nav[^>]*>[\\s\\S]*?</nav>"
        let footerPattern = "<footer[^>]*>[\\s\\S]*?</footer>"
        for pattern in [navPattern, footerPattern] {
            s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        // Replace block elements with newlines
        for tag in ["p", "div", "br", "h1", "h2", "h3", "li", "tr"] {
            s = s.replacingOccurrences(of: "</\(tag)>", with: "\n", options: .regularExpression)
        }
        // Remove remaining tags
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        // Decode common entities
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        return s
    }
}

private struct WebSearchResponse: Decodable {
    let results: [WebSearchResult]
}

private struct WebSearchResult: Decodable {
    let title: String
    let url: String
    let content: String?
}

private struct WebFetchResponse: Decodable {
    let title: String?
    let content: String?
    let links: [String]?
}

private struct WebSearchErrorResponse: Decodable {
    let error: String?
}
