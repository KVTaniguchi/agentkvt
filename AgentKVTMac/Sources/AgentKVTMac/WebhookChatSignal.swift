import Foundation

/// Body for the optional chat-wake POST on the same port as ``WebhookListener``.
///
/// Send **only** this JSON (no dropzone write, no webhook missions): `{"agentkvt":"process_chat"}`
/// Use from the LAN (e.g. Shortcuts, curl) when CloudKit is unavailable or you want to nudge the runner immediately.
public enum WebhookChatSignal {
    public static func matches(_ body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return false }
        struct Payload: Decodable { let agentkvt: String }
        guard let decoded = try? JSONDecoder().decode(Payload.self, from: data) else { return false }
        return decoded.agentkvt == "process_chat"
    }
}
