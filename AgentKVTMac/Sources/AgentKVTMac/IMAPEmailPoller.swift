import Foundation

/// Polls an IMAP mailbox for unseen messages and writes each as an `.eml` file into the
/// agent's inbox directory. The existing `EmailIngestor` + `MissionExecutionQueue` pipeline
/// picks up the files from there — no direct coupling between the two.
///
/// The IMAP fetch logic runs via a small Python 3 script written to `~/.agentkvt/imap_fetch.py`
/// on first use. Python 3 ships with macOS and `imaplib` is stdlib — no external dependencies.
actor IMAPEmailPoller {

    private let settings: RunnerSettings
    private let inboxDir: URL
    private var timer: DispatchSourceTimer?
    private var isPolling = false
    private var scriptInstalled = false

    init(settings: RunnerSettings, inboxDir: URL) {
        self.settings = settings
        self.inboxDir = inboxDir
    }

    // MARK: - Lifecycle

    func start() {
        let interval = settings.imapPollSeconds
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now(), repeating: .seconds(interval))
        t.setEventHandler { [weak self] in
            Task { await self?.poll() }
        }
        t.resume()
        timer = t
        print("[IMAPEmailPoller] Started — host=\(settings.imapHost ?? "?") mailbox=\(settings.imapMailbox) interval=\(interval)s")
    }

    // MARK: - Poll

    private func poll() async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        do {
            let scriptURL = try installScript()
            let written = try await runFetch(scriptURL: scriptURL)
            if !written.isEmpty {
                print("[IMAPEmailPoller] Wrote \(written.count) new email(s) to inbox")
            }
        } catch {
            print("[IMAPEmailPoller] Poll failed: \(error)")
        }
    }

    // MARK: - Script installation

    /// Writes the embedded Python script to `~/.agentkvt/imap_fetch.py` on first use.
    /// Re-writes if the file is missing (e.g. after a manual cleanup).
    private func installScript() throws -> URL {
        let scriptURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".agentkvt/imap_fetch.py", directoryHint: .notDirectory)

        if !scriptInstalled || !FileManager.default.fileExists(atPath: scriptURL.path) {
            try imapFetchScriptSource.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o755))],
                ofItemAtPath: scriptURL.path
            )
            scriptInstalled = true
        }
        return scriptURL
    }

    // MARK: - Fetch execution

    private func runFetch(scriptURL: URL) async throws -> [String] {
        guard let host = settings.imapHost,
              let username = settings.imapUsername,
              let password = settings.imapPassword else {
            throw IMAPPollerError.missingCredentials
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            scriptURL.path,
            host,
            String(settings.imapPort),
            username,
            password,
            settings.imapMailbox,
            inboxDir.path
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }
            process.terminationHandler = { p in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()

                guard p.terminationStatus == 0 else {
                    let msg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(no output)"
                    continuation.resume(throwing: IMAPPollerError.scriptFailed(msg))
                    return
                }

                guard
                    let outStr = String(data: outData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    let paths = try? JSONSerialization.jsonObject(with: Data(outStr.utf8)) as? [String]
                else {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: paths)
            }
        }
    }

    // MARK: - Error

    enum IMAPPollerError: Error, CustomStringConvertible {
        case missingCredentials
        case scriptFailed(String)

        var description: String {
            switch self {
            case .missingCredentials:
                return "IMAP credentials incomplete — set AGENTKVT_IMAP_HOST, AGENTKVT_IMAP_USERNAME, and AGENTKVT_IMAP_PASSWORD"
            case .scriptFailed(let msg):
                return "imap_fetch.py exited non-zero: \(msg)"
            }
        }
    }
}

// MARK: - Embedded Python script

/// Fetches unseen messages from an IMAP mailbox and writes them as .eml files.
/// Fetching with RFC822 (not RFC822.PEEK) marks each message \Seen on the server.
private let imapFetchScriptSource = """
#!/usr/bin/env python3
\"\"\"
AgentKVT IMAP fetcher.
Usage: imap_fetch.py host port username password mailbox output_dir
Prints a JSON array of written .eml file paths to stdout.
\"\"\"
import imaplib
import json
import os
import sys
from datetime import datetime


def main():
    if len(sys.argv) != 7:
        print(
            "Usage: imap_fetch.py host port username password mailbox output_dir",
            file=sys.stderr,
        )
        sys.exit(1)

    host, port_str, username, password, mailbox, output_dir = sys.argv[1:]
    os.makedirs(output_dir, exist_ok=True)
    written = []

    with imaplib.IMAP4_SSL(host, int(port_str)) as mail:
        mail.login(username, password)
        status, _ = mail.select(mailbox, readonly=False)
        if status != "OK":
            print(f"SELECT {mailbox!r} failed", file=sys.stderr)
            sys.exit(1)

        status, id_data = mail.search(None, "UNSEEN")
        if status != "OK" or not id_data or not id_data[0]:
            print(json.dumps([]))
            return

        for msg_id in id_data[0].split():
            # RFC822 (without PEEK) marks the message as Seen on most servers.
            status, parts = mail.fetch(msg_id, "(RFC822)")
            if status != "OK" or not parts:
                continue
            for part in parts:
                if not isinstance(part, tuple):
                    continue
                raw = part[1]
                if not isinstance(raw, bytes):
                    continue
                ts = datetime.now().strftime("%Y%m%d-%H%M%S")
                filename = f"imap-{msg_id.decode()}-{ts}.eml"
                filepath = os.path.join(output_dir, filename)
                with open(filepath, "wb") as f:
                    f.write(raw)
                written.append(filepath)
                break  # one file per message ID

    print(json.dumps(written))


if __name__ == "__main__":
    main()
"""
