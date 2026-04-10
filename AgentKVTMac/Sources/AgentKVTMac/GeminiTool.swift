import Foundation

/// Gemini LLM Tool: sends a question to Google's Gemini 2.0 Flash model and returns a
/// plain-text answer. Use for factual/reasoning questions that don't need live web data
/// (trip advice, general knowledge, summarisation, comparison, recommendations, etc.).
/// Much cheaper on context than a web search — returns a concise answer instead of
/// raw page HTML.
///
/// Requires GEMINI_API_KEY (free tier available at aistudio.google.com).
public func makeGeminiAskTool(apiKey: String? = nil) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "ask_gemini",
        name: "ask_gemini",
        description: """
            Ask Google Gemini 2.0 Flash a factual or reasoning question and get a concise answer.
            Use this INSTEAD of web_search when the question does not need real-time data —
            e.g. "what's the weather typically like in San Diego in April", "what theme park tips
            should I know for Universal Orlando", "compare these two options", "what does this
            mean", etc.
            Returns a plain-text answer. Does NOT browse the web or access live prices/schedules.
            """,
        parameters: .init(
            type: "object",
            properties: [
                "question": .init(
                    type: "string",
                    description: "The question or prompt to send to Gemini. Be specific and include any relevant context."
                )
            ],
            required: ["question"]
        ),
        handler: { args in
            guard let question = args["question"] as? String,
                  !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "Error: question is required and must be non-empty."
            }
            return await GeminiTool.ask(
                question: question.trimmingCharacters(in: .whitespacesAndNewlines),
                apiKeyOverride: apiKey
            )
        }
    )
}

enum GeminiTool {
    private static let apiURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent")!

    static func ask(question: String, apiKeyOverride: String? = nil) async -> String {
        let resolvedKey = apiKeyOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let envKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiKey = [resolvedKey, envKey].compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            return "Error: GOOGLE_API_KEY must be set. Get a free key at aistudio.google.com."
        }

        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            return "Error: failed to construct Gemini API URL."
        }

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": question]]]
            ],
            "generationConfig": [
                "maxOutputTokens": 1024,
                "temperature": 0.2
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return "Error: failed to encode request body."
        }
        request.httpBody = httpBody

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return "Error: Gemini request failed (network error)."
        }

        guard http.statusCode == 200 else {
            let msg = (try? JSONDecoder().decode(GeminiErrorResponse.self, from: data))?.error.message ?? "HTTP \(http.statusCode)"
            return "Error: Gemini API returned an error: \(msg)"
        }

        do {
            let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
            let text = decoded.candidates.first?.content.parts.first?.text ?? ""
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Gemini returned an empty response."
                : text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "Error: failed to decode Gemini response: \(error.localizedDescription)"
        }
    }
}

private struct GeminiResponse: Decodable {
    let candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Decodable {
    let content: GeminiContent
}

private struct GeminiContent: Decodable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Decodable {
    let text: String
}

private struct GeminiErrorResponse: Decodable {
    let error: GeminiError
}

private struct GeminiError: Decodable {
    let message: String
}
