import Foundation

/// "Only Me" notification tool: destination is fixed (env or keychain); only subject and body from LLM.
/// The agent cannot specify the recipient — it is physically impossible.
public func makeSendNotificationEmailTool(
    destinationEmail: String,
    sendVia: SendNotificationEmailTool.SendMethod = .defaultOutbox
) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "send_notification_email",
        name: "send_notification_email",
        description: "Send a notification email to the user. Use for alerts or summaries. Only subject and body can be specified.",
        parameters: .init(
            type: "object",
            properties: [
                "subject": .init(type: "string", description: "Email subject line"),
                "body": .init(type: "string", description: "Email body text")
            ],
            required: ["subject", "body"]
        ),
        handler: { args in
            guard let subject = args["subject"] as? String, !subject.isEmpty else {
                return "Error: subject is required and must be non-empty."
            }
            let body = (args["body"] as? String) ?? ""
            return SendNotificationEmailTool.send(
                to: destinationEmail,
                subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                body: body,
                via: sendVia
            )
        }
    )
}

public enum SendNotificationEmailTool {
    /// How to deliver the email: outbox file (user forwards via script) or system mail command.
    public enum SendMethod {
        case outbox(directory: URL)
        case mailCommand

        public static var defaultOutbox: SendMethod {
            .outbox(directory: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".agentkvt/outbox", directoryHint: .isDirectory))
        }
    }

    static func send(to destination: String, subject: String, body: String, via: SendMethod) -> String {
        guard !destination.isEmpty else {
            return "Error: NOTIFICATION_EMAIL not configured; cannot send."
        }
        switch via {
        case .outbox(let dir):
            let formatter = ISO8601DateFormatter()
            let filename = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-") + ".txt"
            let fileURL = dir.appending(path: filename)
            let content = "To: \(destination)\nSubject: \(subject)\n\n\(body)"
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                return "Queued notification to outbox: \(fileURL.path)"
            } catch {
                return "Error writing to outbox: \(error)"
            }
        case .mailCommand:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mail")
            process.arguments = ["-s", subject, destination]
            let pipe = Pipe()
            process.standardInput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                pipe.fileHandleForWriting.write(Data(body.utf8))
                try pipe.fileHandleForWriting.close()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    return "Notification email sent to \(destination)."
                }
                return "mail command exited with status \(process.terminationStatus)."
            } catch {
                return "Error sending mail: \(error)"
            }
        }
    }
}
