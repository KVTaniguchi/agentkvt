import Foundation

/// MCP tool: returns the next pending email from the Agent Inbox (intent + sanitized general content only).
/// The EmailIngestor must have already parsed and sanitized the email; this tool only passes intent and content to the agent.
public func makeIncomingEmailTriggerTool(ingestor: EmailIngestor) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "incoming_email_trigger",
        name: "incoming_email_trigger",
        description: "Get the next pending email from the Agent Inbox. Returns only the intent (e.g. subject) and general content; all PII has been stripped. Use this to respond to email triggers without exposing personal data.",
        parameters: .init(
            type: "object",
            properties: [:],
            required: []
        ),
        handler: { _ in
            guard let next = ingestor.popNext() else {
                return "No pending emails."
            }
            return "Intent: \(next.intent)\n\nGeneral content:\n\(next.generalContent)"
        }
    )
}
