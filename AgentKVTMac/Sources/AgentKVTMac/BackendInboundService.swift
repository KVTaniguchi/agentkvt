import Foundation

/// Reads pending inbound files from the backend and writes them to the local dropzone.
public actor BackendInboundService {
    private let backendClient: BackendAPIClient
    private let directory: URL

    public init(backendClient: BackendAPIClient, directory: URL = DropzoneService.defaultDirectory) {
        self.backendClient = backendClient
        self.directory = directory
    }

    public func syncInboundFiles(limit: Int = 100) async {
        do {
            let files = try await backendClient.fetchPendingInboundFiles(limit: limit)
            guard !files.isEmpty else { return }

            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            var writtenCount = 0
            for file in files {
                guard let fileBase64 = file.fileBase64,
                      let data = Data(base64Encoded: fileBase64) else {
                    print("[BackendInboundService] Missing or invalid file payload for \(file.id)")
                    continue
                }

                let destination = directory.appendingPathComponent(file.fileName)
                do {
                    try data.write(to: destination, options: [.atomic])
                    _ = try await backendClient.markInboundFileProcessed(id: file.id)
                    writtenCount += 1
                } catch {
                    print("[BackendInboundService] Failed to write \(file.fileName): \(error)")
                }
            }

            if writtenCount > 0 {
                print("[BackendInboundService] Synced \(writtenCount) inbound file(s) to \(directory.path)")
            }
        } catch {
            print("[BackendInboundService] Sync failed: \(error)")
        }
    }
}
