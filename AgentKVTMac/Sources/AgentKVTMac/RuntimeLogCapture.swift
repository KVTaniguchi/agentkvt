import Darwin
import Foundation

/// Mirrors stdout/stderr to a persistent log file so the signed Mac app can be
/// inspected over SSH even when its primary console is Xcode.
public enum RuntimeLogCapture {
    public static let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".agentkvt/logs", directoryHint: .isDirectory)
    public static let defaultFileURL = defaultDirectory.appending(path: "agentkvt-mac.log")
    public static let sharedContainerLogFileURL = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: sharedAppGroupIdentifier)?
        .appending(path: "Library/Logs/agentkvt-mac.log")

    private static let state = State()

    @discardableResult
    public static func configure(
        processLabel: String,
        logFileURL: URL? = nil
    ) async -> URL {
        await state.configure(processLabel: processLabel, logFileURL: logFileURL)
    }

    actor State {
        private var isConfigured = false
        private var pipe: Pipe?
        private var readSource: DispatchSourceRead?
        private var logHandle: FileHandle?
        private var originalStdout = FileHandle.standardOutput
        private var originalStderr = FileHandle.standardError

        func configure(processLabel: String, logFileURL: URL?) -> URL {
            let destination = resolvedLogFileURL(explicitURL: logFileURL)
            guard !isConfigured else {
                return destination
            }

            prepareLogFile(at: destination)

            let fileHandle = try? FileHandle(forWritingTo: destination)
            let _ = try? fileHandle?.seekToEnd()

            let stdoutFD = dup(STDOUT_FILENO)
            let stderrFD = dup(STDERR_FILENO)
            if stdoutFD >= 0 {
                originalStdout = FileHandle(fileDescriptor: stdoutFD, closeOnDealloc: true)
            }
            if stderrFD >= 0 {
                originalStderr = FileHandle(fileDescriptor: stderrFD, closeOnDealloc: true)
            }

            let capturePipe = Pipe()
            pipe = capturePipe
            logHandle = fileHandle

            setvbuf(stdout, nil, _IONBF, 0)
            setvbuf(stderr, nil, _IONBF, 0)
            dup2(capturePipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
            dup2(capturePipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

            let mirroredStdout = originalStdout
            let mirroredLogHandle = fileHandle
            let timestampSink = TimestampingSink(
                fileHandle: mirroredLogHandle,
                mirroredStdout: mirroredStdout
            )
            let source = DispatchSource.makeReadSource(
                fileDescriptor: capturePipe.fileHandleForReading.fileDescriptor,
                queue: DispatchQueue(label: "RuntimeLogCapture.pipe")
            )
            source.setEventHandler {
                let data = capturePipe.fileHandleForReading.availableData
                guard !data.isEmpty else { return }
                timestampSink.consume(data)
            }
            source.setCancelHandler {
                timestampSink.flushRemainder()
                try? capturePipe.fileHandleForReading.close()
                try? capturePipe.fileHandleForWriting.close()
                try? mirroredLogHandle?.close()
            }
            source.resume()
            readSource = source

            isConfigured = true

            let sessionHeader = """

            ===== AgentKVT session started \(timestamp()) [\(processLabel)] pid=\(ProcessInfo.processInfo.processIdentifier) =====
            """
            writeDirect(sessionHeader + "\n", to: fileHandle, mirroredStdout: mirroredStdout)

            return destination
        }

        private func resolvedLogFileURL(explicitURL: URL?) -> URL {
            if let explicitURL {
                return explicitURL
            }
            if let customPath = ProcessInfo.processInfo.environment["AGENTKVT_LOG_FILE"], !customPath.isEmpty {
                return URL(fileURLWithPath: (customPath as NSString).expandingTildeInPath)
            }
            if let sharedContainerLogFileURL = RuntimeLogCapture.sharedContainerLogFileURL {
                return sharedContainerLogFileURL
            }
            return RuntimeLogCapture.defaultFileURL
        }

        private func prepareLogFile(at url: URL) {
            let directory = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                let _ = FileManager.default.createFile(atPath: url.path, contents: nil)
            }
        }

        private func writeDirect(_ string: String, to fileHandle: FileHandle?, mirroredStdout: FileHandle) {
            guard let data = string.data(using: .utf8) else { return }
            try? fileHandle?.write(contentsOf: data)
            try? mirroredStdout.write(contentsOf: data)
        }

        private func timestamp() -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: Date())
        }
    }
}

private final class TimestampingSink: @unchecked Sendable {
    private var bufferedData = Data()
    private let fileHandle: FileHandle?
    private let mirroredStdout: FileHandle
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(fileHandle: FileHandle?, mirroredStdout: FileHandle) {
        self.fileHandle = fileHandle
        self.mirroredStdout = mirroredStdout
    }

    func consume(_ data: Data) {
        bufferedData.append(data)

        while let newlineIndex = bufferedData.firstIndex(of: 0x0A) {
            let lineData = bufferedData.prefix(upTo: newlineIndex)
            bufferedData.removeSubrange(...newlineIndex)
            writeTimestampedLine(lineData)
        }
    }

    func flushRemainder() {
        guard !bufferedData.isEmpty else { return }
        writeTimestampedLine(bufferedData)
        bufferedData.removeAll(keepingCapacity: false)
    }

    private func writeTimestampedLine<S: DataProtocol>(_ lineData: S) {
        var payload = Data()
        payload.append("[\(formatter.string(from: Date()))] ".data(using: .utf8)!)
        payload.append(contentsOf: lineData)
        payload.append(0x0A)
        try? fileHandle?.write(contentsOf: payload)
        try? mirroredStdout.write(contentsOf: payload)
    }
}
