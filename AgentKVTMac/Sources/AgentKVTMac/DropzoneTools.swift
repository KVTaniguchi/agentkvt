import Foundation
import PDFKit

public func makeListDropzoneFilesTool(directory: URL) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "list_dropzone_files",
        name: "list_dropzone_files",
        description: "List all files currently available in the inbound dropzone. Use this to discover external context files.",
        parameters: .init(
            type: "object",
            properties: [:],
            required: []
        ),
        handler: { _ in
            return await DropzoneToolsHandler.listFiles(directory: directory)
        }
    )
}

public func makeReadDropzoneFileTool(directory: URL) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "read_dropzone_file",
        name: "read_dropzone_file",
        description: "Read the contents of a specific file from the inbound dropzone. Supports PDF, CSV, and TXT.",
        parameters: .init(
            type: "object",
            properties: [
                "filename": .init(type: "string", description: "The name of the file to read (e.g. 'resume.pdf').")
            ],
            required: ["filename"]
        ),
        handler: { args in
            guard let filename = args["filename"] as? String, !filename.isEmpty else {
                return "Error: filename is required."
            }
            return await DropzoneToolsHandler.readFile(filename: filename, directory: directory)
        }
    )
}

enum DropzoneToolsHandler {
    static func listFiles(directory: URL) async -> String {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return "Unable to read directory."
        }
        var files: [String] = []
        while let url = enumerator.nextObject() as? URL {
            guard let resource = try? url.resourceValues(forKeys: [.isRegularFileKey]), resource.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            if ["pdf", "csv", "txt"].contains(ext) {
                files.append(url.lastPathComponent)
            }
        }
        if files.isEmpty {
            return "The dropzone is currently empty."
        }
        return "Available files in dropzone:\n" + files.joined(separator: "\n")
    }

    static func readFile(filename: String, directory: URL) async -> String {
        // Prevent path traversal
        let safeFilename = URL(fileURLWithPath: filename).lastPathComponent
        let url = directory.appendingPathComponent(safeFilename)
        if !FileManager.default.fileExists(atPath: url.path) {
            return "Error: File '\(safeFilename)' not found."
        }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "txt", "csv":
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return String(text.prefix(100_000))
            } else {
                return "Error reading text file."
            }
        case "pdf":
            guard let doc = PDFDocument(url: url) else { return "Error parsing PDF." }
            let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
            return String(text.prefix(100_000))
        default:
            return "Error: Unsupported file type."
        }
    }
}
