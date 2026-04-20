# AgentMail Integration

AgentKVT can use [AgentMail](https://docs.agentmail.to/api-reference) as its
email platform instead of IMAP.

This keeps the existing local inbox pipeline intact on the Mac runner while
swapping the upstream transport from mailbox polling to the AgentMail API.

## Current Scope

The current integration adds:

- AgentMail-backed inbox creation or reuse
- polling unread messages into `~/.agentkvt/inbox/*.eml`
- marking messages `processed` / `read` after import
- sending notification email through the AgentMail inbox when
  `NOTIFICATION_EMAIL` is configured
- bridge support for listing threads and replying to messages

It does not yet expose a general-purpose outbound reply tool to the LLM.

## Important Limitation

AgentMail's AI onboarding docs still say a human must create the initial
AgentMail account and API key in the AgentMail dashboard. AgentKVT can then use
that API key programmatically to create inboxes, send, list threads, and reply.

## Install The Python SDK

Create a Python environment on the Mac and install the official SDK:

```bash
python3 -m venv ~/.venvs/agentmail
~/.venvs/agentmail/bin/pip install agentmail
```

Then point the runner at that interpreter.

## Runner Config

Add these keys to `~/.agentkvt/agentkvt-runner.plist`:

```xml
<key>AGENTMAIL_API_KEY</key>
<string>am_your_api_key</string>

<key>AGENTMAIL_PYTHON_EXECUTABLE</key>
<string>/Users/your-user/.venvs/agentmail/bin/python3</string>

<key>AGENTMAIL_DISPLAY_NAME</key>
<string>Agent KVT</string>

<key>AGENTMAIL_USERNAME</key>
<string>agentkvt</string>

<key>AGENTMAIL_DOMAIN</key>
<string>agentmail.to</string>

<key>AGENTMAIL_INBOX_CLIENT_ID</key>
<string>agentkvt-email-v1</string>

<key>AGENTMAIL_POLL_SECONDS</key>
<integer>60</integer>
```

Optional:

```xml
<key>AGENTMAIL_INBOX_ID</key>
<string>agentkvt@agentmail.to</string>
```

If `AGENTMAIL_INBOX_ID` is omitted, the runner will create or reuse an inbox
through AgentMail and remember the inbox id locally in
`~/.agentkvt/agentmail-inbox.json`.

## How It Works

1. The Mac runner uses the official Python `agentmail` SDK.
2. `AgentMailPoller` lists unread messages for the configured inbox.
3. Each unread message is written into the local Agent Inbox as a pseudo-`.eml`
   file.
4. The existing `EmailIngestor` and `incoming_email_trigger` path continues to
   work without needing a second ingestion architecture.
5. Imported messages are relabeled in AgentMail as `processed` and `read`.
6. **Agent Identity Sync**: As part of its 15-second heartbeat (`RegistrationsController#upsert`), the Mac runner passes its resolved AgentMail inbox ID (email address) to the server. The server automatically upserts this setting into the workspace's persistent `AgentIdentity#from_email`, making the remote identity available securely to the iOS UI.

## Sending Notifications Through AgentMail

If both `AGENTMAIL_API_KEY` and `NOTIFICATION_EMAIL` are configured,
`send_notification_email` will send through AgentMail instead of the local
outbox or `/usr/bin/mail`.

This preserves the existing fixed-destination safety model while making the
message originate from the agent's own inbox.

## Thread / Reply Support

The bridge also supports:

- `inboxes.threads.list()`
- `inboxes.messages.reply()`

These are wired into the Mac-side bridge and are available for future agent or
backend features, but are not yet exposed as autonomous LLM tools.
