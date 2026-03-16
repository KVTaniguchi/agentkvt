import Foundation
import SwiftData
import ManagerCore

/// Reads unprocessed InboundFile records from SwiftData and writes them to the local inbound directory.
public final class CloudInboundService {
    private let modelContext: ModelContext
    private let directory: URL
    private let queue = DispatchQueue(label: "CloudInboundService")

    public init(modelContext: ModelContext, directory: URL = DropzoneService.defaultDirectory) {
        self.modelContext = modelContext
        self.directory = directory
    }

    public func syncInboundFiles() {
        queue.sync {
            do {
                let descriptor = FetchDescriptor<InboundFile>(
                    predicate: #Predicate { !$0.isProcessed },
                    sortBy: [SortDescriptor(\.timestamp)]
                )
                let files = try modelContext.fetch(descriptor)
                guard !files.isEmpty else { return }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var writtenCount = 0
                for file in files {
                    let destination = directory.appendingPathComponent(file.fileName)
                    do {
                        try file.fileData.write(to: destination, options: [.atomic])
                        file.isProcessed = true
                        writtenCount += 1
                    } catch {
                        print("CloudInboundService: failed to write inbound file \(file.fileName): \(error)")
                    }
                }
                if modelContext.hasChanges {
                    try modelContext.save()
                }
                if writtenCount > 0 {
                    print("CloudInboundService: synced \(writtenCount) inbound file(s) to \(directory.path)")
                }
            } catch {
                print("CloudInboundService error: \(error)")
            }
        }
    }
}

