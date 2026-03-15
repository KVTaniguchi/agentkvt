import Foundation

/// Agent Inbox: watches a directory for .eml files (or polls), parses and sanitizes,
/// then enqueues (intent, general_content) for the incoming_email_trigger tool.
public final class EmailIngestor {
    public static let defaultInboxDirectory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".agentkvt/inbox", directoryHint: .isDirectory)

    public struct PendingEmail: Sendable {
        public let intent: String
        public let generalContent: String
    }

    public let directory: URL
    private let sanitizer = EmailSanitizer()
    private let queue = DispatchQueue(label: "EmailIngestor.queue")
    private var pending: [PendingEmail] = []
    private var processedPaths: Set<String> = []
    private var timer: DispatchSourceTimer?

    public init(directory: URL = EmailIngestor.defaultInboxDirectory) {
        self.directory = directory
    }

    public func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Start polling the inbox directory for new .eml files.
    public func startWatching(pollInterval: TimeInterval = 15) {
        ensureDirectory()
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: pollInterval)
        t.setEventHandler { [weak self] in self?.scan() }
        t.resume()
        timer = t
    }

    public func stopWatching() {
        timer?.cancel()
        timer = nil
    }

    /// Called by incoming_email_trigger tool: return next pending (intent, content) and remove it.
    public func popNext() -> PendingEmail? {
        queue.sync {
            guard !pending.isEmpty else { return nil }
            return pending.removeFirst()
        }
    }

    /// One-time scan for .eml files.
    public func scan() {
        queue.async { [weak self] in
            self?._scan()
        }
    }

    private func _scan() {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "eml" else { continue }
            let path = url.path
            guard !processedPaths.contains(path) else { continue }
            guard let (intent, content) = parseEml(url: url) else { continue }
            let sanitized = sanitizer.sanitize(content)
            pending.append(PendingEmail(intent: intent, generalContent: sanitized))
            processedPaths.insert(path)
        }
    }

    private func parseEml(url: URL) -> (String, String)? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var subject = ""
        var bodyStart = raw.startIndex
        let lines = raw.components(separatedBy: .newlines)
        for line in lines {
            if line.lowercased().hasPrefix("subject:") {
                subject = line.dropFirst(8).trimmingCharacters(in: .whitespaces)
                if subject.hasPrefix("\"") { subject = String(subject.dropFirst().dropLast()) }
            }
            if line.isEmpty {
                if let idx = raw.range(of: "\n\n", range: bodyStart..<raw.endIndex)?.upperBound {
                    bodyStart = idx
                }
                break
            }
        }
        let body = String(raw[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let intent = subject.isEmpty ? (lines.first ?? "").prefix(200).description : subject
        return (intent, body.isEmpty ? "(no body)" : body)
    }
}
