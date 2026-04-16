# Email Ingestion

The Mac agent polls `kvtingest@gmail.com` via IMAP and processes each incoming email
as an agent task. Subscribe to mailing lists and newsletters using that address
instead of your personal email — the agent extracts key findings and logs them
via the Agent Log for review in the iOS app.

## Architecture

```
kvtingest@gmail.com   (subscribe mailing lists here)
        │
        │  IMAPEmailPoller polls every 5 min via Python imaplib
        ▼
~/.agentkvt/inbox/*.eml
        │
        │  EmailIngestor watches directory + sanitizes content
        ▼
AgentExecutionQueue dispatches .emailFile event
        │
        │  incoming_email_trigger tool reads next pending email
        ▼
Agent logs findings via AgentLog
        │
        ▼
iOS Agent Log tab
```

No Rails changes. No iOS changes. The IMAP poller slots into the existing
email pipeline at the inbox directory boundary.

## Sanitization

Before any email content reaches the agent or LLM:

- **SSN / gov IDs** — digits in SSN or long ID-like patterns → `[REDACTED_SSN]` / `[REDACTED_ID]`
- **Bank account numbers** — 4×4 digit groups or 12+ consecutive digits → `[REDACTED_ACCOUNT]`
- **Full names** — heuristic Title Case 2–3 word phrases → `[NAME]` (the word "User" is preserved)

Implemented with regex for speed; a local "Sanitizer" model can be added later for stronger name/entity redaction.

The `incoming_email_trigger` tool returns only **intent** (e.g. subject) and **general content** (sanitized body). The agent uses that to drive actions without ever seeing raw PII.

---

## One-time setup

### 1. Enable IMAP and generate an app password

In `kvtingest@gmail.com`:

- Gmail Settings → See all settings → Forwarding and POP/IMAP → Enable IMAP → Save
- Google Account → Security → 2-Step Verification → App passwords
- Create one labelled "AgentKVT" — copy the 16-character password

### 2. Configure the agent

Add these keys to `~/.agentkvt/agentkvt-runner.plist` on the server Mac:

```xml
<key>AGENTKVT_IMAP_HOST</key>
<string>imap.gmail.com</string>

<key>AGENTKVT_IMAP_PORT</key>
<integer>993</integer>

<key>AGENTKVT_IMAP_USERNAME</key>
<string>kvtingest@gmail.com</string>

<key>AGENTKVT_IMAP_PASSWORD</key>
<string>xxxx xxxx xxxx xxxx</string>
```

Optional (defaults shown):

```xml
<key>AGENTKVT_IMAP_MAILBOX</key>
<string>INBOX</string>

<key>AGENTKVT_IMAP_POLL_SECONDS</key>
<integer>300</integer>
```

Restart the Mac app to pick up the new config:

```bash
launchctl kickstart -k gui/$(id -u)/com.agentkvt.api
```

### 3. Create the "Mailing List Processor" mission

Open the iOS app → Missions → +

| Field | Value |
|-------|-------|
| Name | Mailing List Processor |
| Schedule | webhook |
| Allowed tools | `incoming_email_trigger` |

System prompt:

```
You process incoming mailing list and newsletter emails.

Call incoming_email_trigger to read the next email.

From the email content, extract the most useful items and summarize them:
- Events or deadlines with dates
- Links or articles worth reading
- Reminders or follow-ups with due dates if mentioned

Provide a concise summary of at most 3 actionable findings per email.
If the email is pure promotional noise with no actionable content, note that and move on.
```

---

## Config reference

| Key | Default | Description |
|-----|---------|-------------|
| `AGENTKVT_IMAP_HOST` | — | IMAP server hostname (required) |
| `AGENTKVT_IMAP_PORT` | `993` | IMAP SSL port |
| `AGENTKVT_IMAP_USERNAME` | — | IMAP login username (required) |
| `AGENTKVT_IMAP_PASSWORD` | — | Gmail app password (required) |
| `AGENTKVT_IMAP_MAILBOX` | `INBOX` | Mailbox to poll |
| `AGENTKVT_IMAP_POLL_SECONDS` | `300` | Poll interval in seconds (minimum 60) |

The poller is disabled unless all three required keys (`HOST`, `USERNAME`, `PASSWORD`) are set.

---

## How it works

`IMAPEmailPoller` is a Swift actor that fires on a repeating timer. On each tick it runs
`~/.agentkvt/imap_fetch.py` (written to disk on first use) via `/usr/bin/python3`.

The script:
1. Connects to `imap.gmail.com:993` over SSL
2. Searches for `UNSEEN` messages
3. Fetches each message body (`RFC822`) — Gmail marks these as read automatically
4. Writes each to `~/.agentkvt/inbox/imap-{id}-{timestamp}.eml`
5. Returns a JSON array of written paths

`EmailIngestor` watches the inbox directory and enqueues each `.eml` for the
`incoming_email_trigger` tool. The Mailing List Processor mission fires and reads the email.

---

## Verification

**1. Smoke-test credentials on the server Mac:**

```bash
python3 ~/.agentkvt/imap_fetch.py \
  imap.gmail.com 993 \
  kvtingest@gmail.com "app password" \
  INBOX ~/.agentkvt/inbox
```

Should print `[]` (no unseen mail) or a JSON array of written `.eml` paths.

**2. End-to-end test:**

Send an email to `kvtingest@gmail.com`. Within 5 minutes a `.eml` should appear in
`~/.agentkvt/inbox/`. Tail the log to confirm:

```bash
tail -f ~/.agentkvt/logs/agentkvt-mac.log | grep -E "IMAP|emailFile"
```

**3. iOS confirmation:**

Processed email findings appear in the iOS Agent Log tab.

**4. Mark-read check:**

The message should appear as read in the Gmail inbox after processing.
