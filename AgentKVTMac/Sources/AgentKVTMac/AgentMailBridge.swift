import Foundation

public actor AgentMailBridge {
    struct InboxInfo: Decodable, Sendable {
        let inboxId: String
        let displayName: String?
        let created: Bool?
    }

    struct MessageSummary: Decodable, Sendable {
        let inboxId: String
        let threadId: String?
        let messageId: String
        let labels: [String]
        let timestamp: String?
        let from: String?
        let to: [String]
        let cc: [String]?
        let bcc: [String]?
        let replyTo: [String]?
        let subject: String?
        let preview: String?
        let bodyText: String
        let headers: [String: String]?
    }

    struct ThreadList: Decodable, Sendable {
        struct ThreadSummary: Decodable, Sendable {
            let threadId: String
            let labels: [String]?
            let timestamp: String?
            let senders: [String]?
            let recipients: [String]?
            let subject: String?
        }

        let count: Int?
        let threads: [ThreadSummary]
    }

    struct SendResult: Decodable, Sendable {
        let messageId: String
        let threadId: String
    }

    struct ReplyResult: Decodable, Sendable {
        let messageId: String
        let threadId: String
    }

    private let settings: RunnerSettings
    private let inboxDir: URL
    private let stateDirectory: URL
    private let stateFileURL: URL
    private var scriptInstalled = false
    private var resolvedInboxId: String?

    init(settings: RunnerSettings, inboxDir: URL) {
        self.settings = settings
        self.inboxDir = inboxDir
        self.stateDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".agentkvt", directoryHint: .isDirectory)
        self.stateFileURL = stateDirectory.appending(path: "agentmail-inbox.json", directoryHint: .notDirectory)
    }

    func ensureInbox() async throws -> InboxInfo {
        if let resolvedInboxId, !resolvedInboxId.isEmpty {
            return InboxInfo(inboxId: resolvedInboxId, displayName: settings.agentMailDisplayName, created: false)
        }

        let payload: [String: Any] = [
            "configured_inbox_id": settings.agentMailInboxId ?? "",
            "state_file": stateFileURL.path,
            "display_name": settings.agentMailDisplayName ?? "",
            "username": settings.agentMailUsername ?? "",
            "domain": settings.agentMailDomain ?? "",
            "client_id": settings.agentMailInboxClientId ?? ""
        ]
        let envelope: Envelope<InboxInfo> = try await run(command: "ensure_inbox", payload: payload)
        resolvedInboxId = envelope.result.inboxId
        return envelope.result
    }

    func listUnreadMessages(limit: Int = 25) async throws -> [MessageSummary] {
        let inbox = try await ensureInbox()
        let payload: [String: Any] = [
            "inbox_id": inbox.inboxId,
            "limit": max(1, min(limit, 100)),
            "labels": ["unread"]
        ]
        let envelope: Envelope<[MessageSummary]> = try await run(command: "list_messages", payload: payload)
        return envelope.result
    }

    func markProcessed(messageId: String) async throws {
        let inbox = try await ensureInbox()
        let payload: [String: Any] = [
            "inbox_id": inbox.inboxId,
            "message_id": messageId,
            "add_labels": ["processed", "read"],
            "remove_labels": ["unread"]
        ]
        let _: Envelope<[String: String]> = try await run(command: "update_message_labels", payload: payload)
    }

    func sendMessage(to recipients: [String], subject: String, text: String, html: String? = nil) async throws -> SendResult {
        let inbox = try await ensureInbox()
        let payload: [String: Any] = [
            "inbox_id": inbox.inboxId,
            "to": recipients,
            "subject": subject,
            "text": text,
            "html": html ?? ""
        ]
        let envelope: Envelope<SendResult> = try await run(command: "send_message", payload: payload)
        return envelope.result
    }

    func listThreads(limit: Int = 25) async throws -> ThreadList {
        let inbox = try await ensureInbox()
        let payload: [String: Any] = [
            "inbox_id": inbox.inboxId,
            "limit": max(1, min(limit, 100))
        ]
        let envelope: Envelope<ThreadList> = try await run(command: "list_threads", payload: payload)
        return envelope.result
    }

    func reply(toMessageId messageId: String, recipients: [String]? = nil, text: String, html: String? = nil, replyAll: Bool = false) async throws -> ReplyResult {
        let inbox = try await ensureInbox()
        let payload: [String: Any] = [
            "inbox_id": inbox.inboxId,
            "message_id": messageId,
            "to": recipients ?? [],
            "text": text,
            "html": html ?? "",
            "reply_all": replyAll
        ]
        let envelope: Envelope<ReplyResult> = try await run(command: "reply_message", payload: payload)
        return envelope.result
    }

    func syncUnreadMessagesToInbox() async -> Int {
        do {
            let messages = try await listUnreadMessages()
            guard !messages.isEmpty else { return 0 }

            try FileManager.default.createDirectory(at: inboxDir, withIntermediateDirectories: true)
            var writtenCount = 0
            for message in messages {
                let destination = inboxDir.appending(path: fileName(for: message), directoryHint: .notDirectory)
                guard !FileManager.default.fileExists(atPath: destination.path) else {
                    try await markProcessed(messageId: message.messageId)
                    continue
                }
                let content = renderPseudoEML(for: message)
                do {
                    try content.write(to: destination, atomically: true, encoding: .utf8)
                    try await markProcessed(messageId: message.messageId)
                    writtenCount += 1
                } catch {
                    print("[AgentMailBridge] Failed to persist message \(message.messageId): \(error)")
                }
            }
            return writtenCount
        } catch {
            print("[AgentMailBridge] Inbox sync failed: \(error)")
            return 0
        }
    }

    private func fileName(for message: MessageSummary) -> String {
        let sanitizedMessageId = sanitizeForFilename(message.messageId)
        return "agentmail-\(sanitizedMessageId).eml"
    }

    private func renderPseudoEML(for message: MessageSummary) -> String {
        var headers: [String] = []
        if let from = message.from, !from.isEmpty {
            headers.append("From: \(from)")
        }
        if !message.to.isEmpty {
            headers.append("To: \(message.to.joined(separator: ", "))")
        }
        if let cc = message.cc, !cc.isEmpty {
            headers.append("Cc: \(cc.joined(separator: ", "))")
        }
        if let replyTo = message.replyTo, !replyTo.isEmpty {
            headers.append("Reply-To: \(replyTo.joined(separator: ", "))")
        }
        if let subject = message.subject, !subject.isEmpty {
            headers.append("Subject: \(subject)")
        }
        if let timestamp = message.timestamp, !timestamp.isEmpty {
            headers.append("Date: \(timestamp)")
        }
        headers.append("Message-ID: <\(message.messageId)>")
        if let threadId = message.threadId, !threadId.isEmpty {
            headers.append("X-AgentMail-Thread-ID: \(threadId)")
        }
        headers.append("X-AgentMail-Message-ID: \(message.messageId)")
        headers.append("X-AgentMail-Inbox-ID: \(message.inboxId)")
        if let sourceHeaders = message.headers {
            for key in sourceHeaders.keys.sorted() {
                guard let value = sourceHeaders[key], !value.isEmpty else { continue }
                let normalizedKey = sanitizeHeaderName(key)
                let normalizedValue = value.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
                headers.append("X-AgentMail-Header-\(normalizedKey): \(normalizedValue)")
            }
        }

        let body = message.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(no body)" : message.bodyText
        return headers.joined(separator: "\n") + "\n\n" + body + "\n"
    }

    private func sanitizeForFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        var output = ""
        output.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            if allowed.contains(scalar) {
                output.unicodeScalars.append(scalar)
            } else {
                output.append("-")
            }
        }
        return output
    }

    private func sanitizeHeaderName(_ key: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        var output = ""
        output.reserveCapacity(key.count)
        for scalar in key.unicodeScalars {
            if allowed.contains(scalar) {
                output.unicodeScalars.append(scalar)
            } else {
                output.append("-")
            }
        }
        return output
    }

    private func run<T: Decodable>(command: String, payload: [String: Any]) async throws -> Envelope<T> {
        let scriptURL = try installScript()
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])

        let process = Process()
        process.executableURL = URL(fileURLWithPath: settings.agentMailPythonExecutable)
        process.arguments = [scriptURL.path, command]

        var environment = ProcessInfo.processInfo.environment
        environment["AGENTMAIL_API_KEY"] = settings.agentMailAPIKey
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
                stdin.fileHandleForWriting.write(payloadData)
                try stdin.fileHandleForWriting.close()
            } catch {
                continuation.resume(throwing: AgentMailBridgeError.processLaunchFailed(error.localizedDescription))
                return
            }

            process.terminationHandler = { proc in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()

                guard proc.terminationStatus == 0 else {
                    let message = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(no output)"
                    continuation.resume(throwing: AgentMailBridgeError.commandFailed(message))
                    return
                }

                do {
                    let envelope = try JSONDecoder.agentMail.decode(Envelope<T>.self, from: outData)
                    continuation.resume(returning: envelope)
                } catch {
                    let raw = String(data: outData, encoding: .utf8) ?? "(invalid utf8)"
                    continuation.resume(throwing: AgentMailBridgeError.invalidResponse(raw))
                }
            }
        }
    }

    private func installScript() throws -> URL {
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let scriptURL = stateDirectory.appending(path: "agentmail_bridge.py", directoryHint: .notDirectory)
        if !scriptInstalled || !FileManager.default.fileExists(atPath: scriptURL.path) {
            try agentMailBridgeScriptSource.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o755))],
                ofItemAtPath: scriptURL.path
            )
            scriptInstalled = true
        }
        return scriptURL
    }
}

private struct Envelope<T: Decodable>: Decodable {
    let ok: Bool
    let result: T
}

enum AgentMailBridgeError: Error, LocalizedError {
    case notConfigured
    case processLaunchFailed(String)
    case commandFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AgentMail is not configured. Set AGENTMAIL_API_KEY first."
        case .processLaunchFailed(let message):
            return "AgentMail bridge failed to launch: \(message)"
        case .commandFailed(let message):
            return "AgentMail bridge command failed: \(message)"
        case .invalidResponse(let body):
            return "AgentMail bridge returned invalid JSON: \(body)"
        }
    }
}

private extension JSONDecoder {
    static var agentMail: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

private let agentMailBridgeScriptSource = """
#!/usr/bin/env python3
import html
import json
import os
import re
import sys
from pathlib import Path

try:
    from agentmail import AgentMail
except ImportError:
    print(
        "The Python 'agentmail' package is not installed for this interpreter. "
        "Install it with: pip install agentmail",
        file=sys.stderr,
    )
    sys.exit(3)


def load_payload():
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    return json.loads(raw)


def client():
    api_key = os.getenv("AGENTMAIL_API_KEY", "").strip()
    if not api_key:
        print("AGENTMAIL_API_KEY is required.", file=sys.stderr)
        sys.exit(2)
    return AgentMail(api_key=api_key)


def to_jsonable(value):
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, list):
        return [to_jsonable(x) for x in value]
    if isinstance(value, tuple):
        return [to_jsonable(x) for x in value]
    if isinstance(value, dict):
        return {str(k): to_jsonable(v) for k, v in value.items()}
    if hasattr(value, "model_dump"):
        return to_jsonable(value.model_dump(mode="json"))
    if hasattr(value, "dict"):
        return to_jsonable(value.dict())
    if hasattr(value, "__dict__"):
        return {
            str(k): to_jsonable(v)
            for k, v in value.__dict__.items()
            if not str(k).startswith("_")
        }
    return str(value)


def body_text_for_message(message):
    for candidate in (
        getattr(message, "extracted_text", None),
        getattr(message, "text", None),
        getattr(message, "preview", None),
    ):
        if candidate:
            return candidate

    html_candidate = getattr(message, "extracted_html", None) or getattr(message, "html", None)
    if html_candidate:
        stripped = re.sub(r"<[^>]+>", " ", html_candidate)
        stripped = html.unescape(stripped)
        stripped = re.sub(r"\\s+", " ", stripped).strip()
        if stripped:
            return stripped
        return html_candidate

    return "(no body)"


def serialize_message(message):
    return {
        "inbox_id": getattr(message, "inbox_id", None),
        "thread_id": getattr(message, "thread_id", None),
        "message_id": getattr(message, "message_id", None),
        "labels": list(getattr(message, "labels", None) or []),
        "timestamp": getattr(message, "timestamp", None),
        "from": getattr(message, "from_", None) or getattr(message, "from", None),
        "to": list(getattr(message, "to", None) or []),
        "cc": list(getattr(message, "cc", None) or []),
        "bcc": list(getattr(message, "bcc", None) or []),
        "reply_to": list(getattr(message, "reply_to", None) or []),
        "subject": getattr(message, "subject", None),
        "preview": getattr(message, "preview", None),
        "body_text": body_text_for_message(message),
        "headers": to_jsonable(getattr(message, "headers", None) or {}),
    }


def save_state(path_str, payload):
    if not path_str:
        return
    path = Path(path_str)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload), encoding="utf-8")


def load_state(path_str):
    if not path_str:
        return {}
    path = Path(path_str)
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def ensure_inbox(client_obj, payload):
    configured = (payload.get("configured_inbox_id") or "").strip()
    if configured:
        return {"inbox_id": configured, "display_name": payload.get("display_name"), "created": False}

    state_file = payload.get("state_file")
    state = load_state(state_file)
    remembered = str(state.get("inbox_id", "")).strip()
    if remembered:
        return {
            "inbox_id": remembered,
            "display_name": state.get("display_name") or payload.get("display_name"),
            "created": False,
        }

    create_args = {}
    if payload.get("display_name"):
        create_args["display_name"] = payload["display_name"]
    if payload.get("username"):
        create_args["username"] = payload["username"]
    if payload.get("domain"):
        create_args["domain"] = payload["domain"]
    if payload.get("client_id"):
        create_args["client_id"] = payload["client_id"]

    inbox = client_obj.inboxes.create(**create_args)
    result = {
        "inbox_id": getattr(inbox, "inbox_id"),
        "display_name": getattr(inbox, "display_name", None),
        "created": True,
    }
    save_state(state_file, result)
    return result


def list_messages(client_obj, payload):
    response = client_obj.inboxes.messages.list(
        inbox_id=payload["inbox_id"],
        limit=payload.get("limit"),
        labels=payload.get("labels"),
    )
    messages = getattr(response, "messages", None) or []
    return [serialize_message(message) for message in messages]


def update_message_labels(client_obj, payload):
    message = client_obj.inboxes.messages.update(
        inbox_id=payload["inbox_id"],
        message_id=payload["message_id"],
        add_labels=payload.get("add_labels"),
        remove_labels=payload.get("remove_labels"),
    )
    return {
        "message_id": getattr(message, "message_id", payload["message_id"]),
        "inbox_id": getattr(message, "inbox_id", payload["inbox_id"]),
    }


def send_message(client_obj, payload):
    result = client_obj.inboxes.messages.send(
        payload["inbox_id"],
        to=payload["to"],
        subject=payload["subject"],
        text=payload["text"],
        html=payload.get("html") or None,
    )
    return to_jsonable(result)


def list_threads(client_obj, payload):
    result = client_obj.inboxes.threads.list(
        inbox_id=payload["inbox_id"],
        limit=payload.get("limit"),
    )
    return to_jsonable(result)


def reply_message(client_obj, payload):
    kwargs = {
        "inbox_id": payload["inbox_id"],
        "message_id": payload["message_id"],
        "text": payload["text"],
    }
    if payload.get("html"):
        kwargs["html"] = payload["html"]
    if payload.get("reply_all"):
        kwargs["reply_all"] = True
    recipients = payload.get("to") or []
    if recipients:
        kwargs["to"] = recipients
    result = client_obj.inboxes.messages.reply(**kwargs)
    return to_jsonable(result)


COMMANDS = {
    "ensure_inbox": ensure_inbox,
    "list_messages": list_messages,
    "update_message_labels": update_message_labels,
    "send_message": send_message,
    "list_threads": list_threads,
    "reply_message": reply_message,
}


def main():
    if len(sys.argv) != 2:
        print("Usage: agentmail_bridge.py <command>", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]
    if command not in COMMANDS:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)

    payload = load_payload()
    result = COMMANDS[command](client(), payload)
    print(json.dumps({"ok": True, "result": to_jsonable(result)}))


if __name__ == "__main__":
    main()
"""
