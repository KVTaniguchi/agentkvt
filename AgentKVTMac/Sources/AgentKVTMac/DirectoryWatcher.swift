import Foundation

/// Watches a single directory for new files using DispatchSourceFileSystemObject (.write on the
/// directory fd). Fires `onNewFile` for each file that appears after `start()` is called.
/// Does NOT re-fire for files that already existed at start time.
final class DirectoryWatcher: @unchecked Sendable {
    private let url: URL
    let onNewFile: (URL) -> Void

    private var source: DispatchSourceFileSystemObject?
    private var knownFiles: Set<String> = []

    init(directory: URL, onNewFile: @escaping (URL) -> Void) {
        self.url = directory
        self.onNewFile = onNewFile
    }

    /// Begin watching. Throws if the directory cannot be opened (e.g. does not exist).
    func start() throws {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOENT)
        }

        // Snapshot so we only fire for files that appear AFTER this point.
        knownFiles = Set((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .global(qos: .utility)
        )
        src.setEventHandler { [weak self] in self?.handleChange() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func handleChange() {
        let current = Set((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
        let added = current.subtracting(knownFiles)
        knownFiles = current
        for name in added {
            onNewFile(url.appendingPathComponent(name))
        }
    }
}
