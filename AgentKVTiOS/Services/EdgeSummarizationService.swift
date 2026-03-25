import Foundation
import NaturalLanguage
import SwiftData
import ManagerCore
import UIKit

// MARK: - EdgeSummarizationService

/// On-device email pre-processor for the iOS edge node.
///
/// Responsibilities:
/// 1. Extract named entities from raw email text via `NLTagger` (free, Neural Engine, iOS 12+).
/// 2. Produce a compact 1-3 sentence summary using Apple Intelligence writing tools
///    (`UIWritingToolsCoordinator`, iOS 18.1+) when available, falling back to
///    an extractive first-sentence heuristic on older OS versions.
/// 3. Persist the result as an `IncomingEmailSummary` into the shared SwiftData container
///    so it syncs via CloudKit to the Mac agent for reasoning.
///
/// Call `process(subject:body:)` once per received email. The method is async and
/// safe to call from any actor — all SwiftData writes are dispatched onto `@MainActor`.
@MainActor
public final class EdgeSummarizationService {

    // MARK: - Init

    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public API

    /// Summarize one email and persist the result.
    ///
    /// - Parameters:
    ///   - subject: The email subject line (stored verbatim, not summarized).
    ///   - body: Full plain-text body of the email.
    ///   - classifiedIntent: Optional caller-provided intent tag (e.g. from a regex pre-filter).
    /// - Returns: The persisted `IncomingEmailSummary` record.
    @discardableResult
    public func process(subject: String, body: String, classifiedIntent: String? = nil) async -> IncomingEmailSummary {
        let entities = extractEntities(from: body)
        let summary: String

        if #available(iOS 18.1, *) {
            summary = await summarizeWithWritingTools(text: body) ?? extractiveSummary(body)
        } else {
            summary = extractiveSummary(body)
        }

        let intent = classifiedIntent ?? classifyIntent(subject: subject, body: body)

        let record = IncomingEmailSummary(
            subject: subject,
            summary: summary,
            keyEntities: entities,
            classifiedIntent: intent.isEmpty ? nil : intent,
            summarizedOnDevice: UIDevice.current.name
        )
        modelContext.insert(record)
        try? modelContext.save()
        return record
    }

    // MARK: - Named Entity Recognition

    private func extractEntities(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var entities: [String] = []
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

        tagger.enumerateTags(in: text.startIndex ..< text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            if let tag, tag != .other {
                let entity = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !entity.isEmpty, !entities.contains(entity) {
                    entities.append(entity)
                }
            }
            return true
        }

        return Array(entities.prefix(10))
    }

    // MARK: - Apple Intelligence Summarization (iOS 18.1+)

    @available(iOS 18.1, *)
    private func summarizeWithWritingTools(text: String) async -> String? {
        // UIWritingToolsCoordinator requires a UITextView as its source.
        // We create a minimal off-screen text view, load the content, request
        // a summary rewrite, and extract the result.
        let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        textView.text = text
        textView.isEditable = true

        return await withCheckedContinuation { continuation in
            let coordinator = UIWritingToolsCoordinator(delegate: SummarizationDelegate(continuation: continuation))
            textView.writingToolsCoordinator = coordinator
            // Request a summarization rewrite. The delegate callback resumes the continuation.
            coordinator.requestRewrite(type: .summarize)
        }
    }

    // MARK: - Extractive Fallback

    /// Returns the first 1-3 sentences of the text, up to ~280 characters.
    private func extractiveSummary(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed

        var sentences: [String] = []
        var charCount = 0
        tokenizer.enumerateTokens(in: trimmed.startIndex ..< trimmed.endIndex) { range, _ in
            let sentence = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else { return true }
            sentences.append(sentence)
            charCount += sentence.count
            return sentences.count < 3 && charCount < 280
        }

        return sentences.joined(separator: " ")
    }

    // MARK: - Lightweight Intent Classification

    /// Keyword-based intent tag for routing on the Mac side.
    /// Returns empty string when no pattern matches so the field is stored as nil.
    private func classifyIntent(subject: String, body: String) -> String {
        let combined = (subject + " " + body).lowercased()
        let rules: [(keywords: [String], intent: String)] = [
            (["schedule", "meeting", "call", "invite", "calendar", "zoom", "teams"], "meeting.request"),
            (["invoice", "payment", "due", "amount owed", "billing"],                "invoice.approval"),
            (["pr review", "pull request", "code review", "lgtm"],                   "code.review"),
            (["action required", "urgent", "asap", "immediate"],                     "action.required"),
            (["unsubscribe", "newsletter", "digest", "weekly update"],               "newsletter"),
        ]
        for rule in rules {
            if rule.keywords.contains(where: { combined.contains($0) }) {
                return rule.intent
            }
        }
        return ""
    }
}

// MARK: - UIWritingToolsCoordinator Delegate

/// Minimal delegate that captures the first completed summarization result and
/// resumes the checked continuation exactly once.
@available(iOS 18.1, *)
private final class SummarizationDelegate: NSObject, UIWritingToolsCoordinatorDelegate {

    private var continuation: CheckedContinuation<String?, Never>
    private var hasResumed = false

    init(continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func writingToolsCoordinator(
        _ coordinator: UIWritingToolsCoordinator,
        requestsBatchChangesWith replacements: [UIWritingToolsCoordinator.Replacement],
        for range: NSRange,
        context: UIWritingToolsCoordinator.Context
    ) {
        guard !hasResumed else { return }
        hasResumed = true
        let result = replacements.first.map { String($0.replacement) }
        continuation.resume(returning: result)
    }

    func writingToolsCoordinatorDidCancelOrFail(_ coordinator: UIWritingToolsCoordinator) {
        guard !hasResumed else { return }
        hasResumed = true
        continuation.resume(returning: nil)
    }

    // Required stub
    func writingToolsCoordinator(
        _ coordinator: UIWritingToolsCoordinator,
        requestsContextsFor range: NSRange
    ) async -> [UIWritingToolsCoordinator.Context] {
        []
    }
}
