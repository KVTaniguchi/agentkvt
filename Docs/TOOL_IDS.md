# MCP Tool IDs (for allowedMCPTools)

Use these IDs in `MissionDefinition.allowedMCPTools` to grant a mission access to specific tools. Principle of least privilege: only include the tools each mission needs.

| Tool ID | Description |
|---------|-------------|
| `write_action_item` | Write a dynamic action item (button) for the iOS dashboard. Title and systemIntent from LLM; payload optional. |
| `send_notification_email` | Send a notification email to the user. Destination is fixed (env/keychain); only subject and body from LLM. |
| `github_agent` | Read-only GitHub operations on allowed repositories (list issues). PAT and repo allowlist configured at startup. |
| `fetch_bee_ai_context` | Fetch recent transcriptions/insights from BEE AI wristband API; store summaries in LifeContext or AgentLog. Set BEE_AI_BASE_URL, BEE_AI_API_KEY (optional BEE_AI_INSIGHTS_PATH). |
| `incoming_email_trigger` | Get next pending email from Agent Inbox (intent + sanitized content only; PII stripped). Requires EmailIngestor; inbox dir: ~/.agentkvt/inbox or AGENTKVT_INBOX_DIR. |

For `write_action_item`, `systemIntent` must be one of the values below. Each intent requires specific keys in `payloadJson` — the canonical schema is defined in `ManagerCore/Sources/ManagerCore/SystemIntent.swift` and is also included in the tool description sent to Ollama on every run.

| systemIntent | Required payloadJson keys | Optional payloadJson keys |
|---|---|---|
| `calendar.create` | `eventTitle` (string), `startDate` (ISO-8601) | `durationMinutes` (integer, default 60), `notes` (string) |
| `mail.reply` | `toAddress` (string), `subject` (string), `draftBody` (string) | — |
| `reminder.add` | `reminderTitle` (string) | `dueDate` (ISO-8601), `notes` (string) |
| `url.open` | `url` (absolute URL string) | `label` (string) |

Legacy alias `open_url` is normalized to `url.open`, but new prompts/docs should use canonical values above.

**Prompt requirement:** If `write_action_item` is in a mission's `allowed_mcp_tools`, the mission's `system_prompt` must explicitly mention `write_action_item` — both the iOS authoring UI and the backend enforce this. A mission that runs without ever calling this tool will produce a `"warning"` phase `AgentLog` entry and no visible output on iOS.

Example `allowedMCPTools`: `["write_action_item", "send_notification_email"]` for a mission that only needs to create buttons and email the user.
