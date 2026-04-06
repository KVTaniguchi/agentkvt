import Foundation
import PDFKit

/// Create a tool that reads local files from an explicit allowlist of directories.
/// The LLM provides an absolute or tilde-expanded path; we verify it resolves
/// inside one of the configured allowed directories before reading.
public func makeReadLocalFileTool(allowedDirectories: [URL]) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "read_local_file",
        name: "read_local_file",
        description: """
            Read a local file from one of the configured allowed directories.
            Supports txt, csv, md, json, and pdf formats.
            Use this to read documents such as a resume, notes, or data files stored on the Mac.
            """,
        parameters: .init(
            type: "object",
            properties: [
                "path": .init(
                    type: "string",
                    description: "Absolute or tilde-expanded path (e.g. '~/Documents/resume.pdf'). Must be within a configured allowed directory."
                )
            ],
            required: ["path"]
        ),
        handler: { args in
            guard let rawPath = args["path"] as? String, !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "Error: path is required."
            }
            return ReadLocalFileToolHandler.read(rawPath: rawPath, allowedDirectories: allowedDirectories)
        }
    )
}

enum ReadLocalFileToolHandler {
    static func read(rawPath: String, allowedDirectories: [URL]) -> String {
        let expanded = (rawPath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        let resolvedURL = URL(fileURLWithPath: expanded).standardized

        // Security: path must start with one of the configured allowed directories.
        let allowedPaths = allowedDirectories.map { $0.standardized.path }
        guard allowedPaths.contains(where: { resolvedURL.path.hasPrefix($0) }) else {
            let listed = allowedPaths.isEmpty ? "(none configured — set AGENTKVT_LOCAL_FILE_DIRS)" : allowedPaths.joined(separator: ", ")
            return "Error: '\(resolvedURL.path)' is outside allowed directories. Allowed: \(listed)"
        }

        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            return "Error: File not found at '\(resolvedURL.path)'."
        }

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDir)
        if isDir.boolValue {
            return "Error: Path is a directory, not a file."
        }

        let ext = resolvedURL.pathExtension.lowercased()
        switch ext {
        case "txt", "csv", "md", "json":
            guard let text = try? String(contentsOf: resolvedURL, encoding: .utf8) else {
                return "Error: Could not read file as UTF-8 text."
            }
            let result = String(text.prefix(100_000))
            return result.isEmpty ? "(empty file)" : result
        case "pdf":
            guard let doc = PDFDocument(url: resolvedURL) else {
                return "Error: Could not parse PDF at '\(resolvedURL.lastPathComponent)'."
            }
            let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
            return String(text.prefix(100_000))
        default:
            return "Error: Unsupported file type '\(ext)'. Supported: txt, csv, md, json, pdf."
        }
    }
}
