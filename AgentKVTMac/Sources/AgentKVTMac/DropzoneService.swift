import Foundation
import PDFKit

/// Secure file inbound: monitors a single directory (e.g. ~/.agentkvt/inbound/).
/// Only this folder is read; the agent has no broad system access.
/// When PDF, CSV, or TXT files appear, parses and exposes content for mission context.
public final class DropzoneService: @unchecked Sendable {
    public static let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".agentkvt/inbound", directoryHint: .isDirectory)

    private let directory: URL
    private let queue = DispatchQueue(label: "DropzoneService")
    private var processedFiles: Set<String> = []
    private var contentBuffer: String = ""
    private let maxContentLength: Int
    private var timer: DispatchSourceTimer?
    private let pollInterval: TimeInterval

    public init(directory: URL = DropzoneService.defaultDirectory, maxContentLength: Int = 100_000, pollInterval: TimeInterval = 10) {
        self.directory = directory
        self.maxContentLength = maxContentLength
        self.pollInterval = pollInterval
    }

    /// Call before missions to ensure directory exists.
    public func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Start watching the directory; content is updated periodically.
    public func startWatching() {
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

    /// Return current accumulated content from parsed dropzone files (safe to call from any thread).
    public func getContent() -> String {
        queue.sync {
            _scan()
            return contentBuffer
        }
    }

    /// One-time scan (e.g. when runner is about to run a mission). Call ensureDirectory() first if needed.
    public func scan() {
        queue.async { [weak self] in
            self?._scan()
        }
    }

    private func _scan() {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        var newContent: [String] = []
        while let url = enumerator.nextObject() as? URL {
            guard let resource = try? url.resourceValues(forKeys: [.isRegularFileKey]), resource.isRegularFile == true else { continue }
            let key = url.path
            guard !processedFiles.contains(key) else { continue }
            let ext = url.pathExtension.lowercased()
            guard ["pdf", "csv", "txt"].contains(ext) else { continue }
            if let text = parseFile(url: url, ext: ext) {
                newContent.append("--- \(url.lastPathComponent) ---\n\(text)")
                processedFiles.insert(key)
            }
        }
        if !newContent.isEmpty {
            let appended = contentBuffer.isEmpty ? newContent.joined(separator: "\n\n") : contentBuffer + "\n\n" + newContent.joined(separator: "\n\n")
            contentBuffer = appended.count > maxContentLength ? String(appended.suffix(maxContentLength)) : appended
        }
    }

    private func parseFile(url: URL, ext: String) -> String? {
        switch ext {
        case "txt", "csv":
            return try? String(contentsOf: url, encoding: .utf8)
        case "pdf":
            guard let doc = PDFDocument(url: url) else { return nil }
            return (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
        default:
            return nil
        }
    }
}
