# MCP Tool IDs (for allowedMCPTools)

Use these IDs in `MissionDefinition.allowedMCPTools` to grant a mission access to specific tools. Principle of least privilege: only include the tools each mission needs.

| Tool ID | Description |
|---------|-------------|
| `write_action_item` | Write a dynamic action item (button) for the iOS dashboard. Title and systemIntent from LLM; payload optional. |
| `send_notification_email` | Send a notification email to the user. Destination is fixed (env/keychain); only subject and body from LLM. |
| `github_agent` | Read-only GitHub operations on allowed repositories (list issues). PAT and repo allowlist configured at startup. |
| `fetch_bee_ai_context` | Fetch recent transcriptions/insights from BEE AI wristband API; store summaries in LifeContext or AgentLog. Set BEE_AI_BASE_URL, BEE_AI_API_KEY (optional BEE_AI_INSIGHTS_PATH). |
| `incoming_email_trigger` | Get next pending email from Agent Inbox (intent + sanitized content only; PII stripped). Requires EmailIngestor; inbox dir: ~/.agentkvt/inbox or AGENTKVT_INBOX_DIR. |

For `write_action_item`, `systemIntent` must be one of:

- `calendar.create`
- `mail.reply`
- `reminder.add`
- `url.open`

Legacy alias `open_url` is normalized to `url.open`, but new prompts/docs should use canonical values above.

Example `allowedMCPTools`: `["write_action_item", "send_notification_email"]` for a mission that only needs to create buttons and email the user.
