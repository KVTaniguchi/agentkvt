import Foundation

/// Scans the email inbox directory for .eml files and POSTs each one to the Rails backend.
/// Runs independently of EmailIngestor (which feeds the MCP tool). The backend handles
/// duplicates idempotently via the unique (workspace_id, message_id) index.
public actor BackendEmailService {
    private let backendClient: BackendAPIClient
    private let directory: URL
    private var postedPaths: Set<String> = []
    private var timer: DispatchSourceTimer?

    public init(backendClient: BackendAPIClient, directory: URL) {
        self.backendClient = backendClient
        self.directory = directory
    }

    public func start(pollInterval: TimeInterval = 30) {
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now(), repeating: pollInterval)
        t.setEventHandler { [weak self] in Task { await self?.scan() } }
        t.resume()
        timer = t
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    public func scan() async {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "eml" else { continue }
            let path = url.path
            guard !postedPaths.contains(path) else { continue }
            guard let parsed = parseEml(url: url) else { continue }

            do {
                try await backendClient.postInboundEmail(
                    messageId: parsed.messageId,
                    fromAddress: parsed.fromAddress,
                    subject: parsed.subject,
                    bodyText: parsed.bodyText
                )
                postedPaths.insert(path)
            } catch {
                print("[BackendEmailService] Failed to POST \(url.lastPathComponent): \(error)")
            }
        }
    }

    private struct ParsedEmail {
        let messageId: String
        let fromAddress: String?
        let subject: String?
        let bodyText: String?
    }

    private func parseEml(url: URL) -> ParsedEmail? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var messageId: String?
        var fromAddress: String?
        var subject: String?
        var bodyStartIndex = raw.startIndex

        let lines = raw.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if line.isEmpty {
                // body begins after the first blank line
                let joined = lines.prefix(i + 1).joined(separator: "\n")
                if let range = raw.range(of: joined) {
                    bodyStartIndex = raw.index(range.upperBound, offsetBy: 0)
                }
                break
            }
            let lower = line.lowercased()
            if lower.hasPrefix("message-id:") || lower.hasPrefix("x-agentmail-message-id:") {
                let value = line.drop(while: { $0 != ":" }).dropFirst().trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                if messageId == nil || lower.hasPrefix("x-agentmail-message-id:") {
                    messageId = value.isEmpty ? nil : value
                }
            } else if lower.hasPrefix("from:") {
                fromAddress = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("subject:") {
                subject = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            }
        }

        let body = String(raw[bodyStartIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedMessageId = messageId ?? url.deletingPathExtension().lastPathComponent

        return ParsedEmail(
            messageId: resolvedMessageId,
            fromAddress: fromAddress,
            subject: subject,
            bodyText: body.isEmpty ? nil : body
        )
    }
}
