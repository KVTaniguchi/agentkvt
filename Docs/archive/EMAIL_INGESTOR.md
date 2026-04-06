> **⚠️ HISTORICAL** — This document has been archived. It describes completed work or superseded architecture. See the active docs in `Docs/` for current information.

# Email Ingestor (Agent Inbox)

The agent responds to email triggers via a dedicated **Agent Inbox**. All PII is stripped before the LLM sees the content.

## Inbox directory

- **Default:** `~/.agentkvt/inbox/`
- **Override:** Set `AGENTKVT_INBOX_DIR` (supports `~`).

Place `.eml` files in this folder (e.g. save from Mail.app or use a rule to copy incoming mail here). The ingestor polls the directory, parses each new .eml, sanitizes the body, and enqueues (intent, general content) for the `incoming_email_trigger` tool.

## Sanitization

Before any content is passed to the agent:

- **SSN / gov IDs** — digits in SSN or long ID-like patterns → `[REDACTED_SSN]` / `[REDACTED_ID]`
- **Bank account numbers** — 4×4 digit groups or 12+ consecutive digits → `[REDACTED_ACCOUNT]`
- **Full names** — heuristic Title Case 2–3 word phrases → `[NAME]` (the word "User" is preserved)

Implemented with regex for speed; a local "Sanitizer" model can be added later for stronger name/entity redaction.

## Tool: incoming_email_trigger

When a mission has `incoming_email_trigger` in `allowedMCPTools`, the agent can call this tool to get the next pending email. The tool returns only **intent** (e.g. subject) and **general content** (sanitized body). The agent then uses that to drive actions (e.g. create ActionItems or update LifeContext) without ever seeing raw PII.

## Modularity

The Dropzone and Email Ingestor are separate services. Other users can point the inbox to their own folder or plug in a different ingest (e.g. IMAP) by implementing the same queue interface and sanitization step.
