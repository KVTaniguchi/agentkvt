# Email Ingestion

The Mac agent can poll an IMAP mailbox and automatically process incoming emails as
agent missions. This lets you use a dedicated address (e.g. `familykvtagent@tuta.com`)
as a mailing list holding ground — subscribe to newsletters there instead of your
personal email, and let the agent extract action items.

## Architecture

```
familykvtagent@tuta.com   (public address for subscriptions)
        │
        │  Tuta auto-forward rule
        ▼
familykvtagent.relay@gmail.com   (private relay, IMAP-accessible)
        │
        │  IMAPEmailPoller polls every 5 min via Python imaplib
        ▼
~/.agentkvt/inbox/*.eml
        │
        │  EmailIngestor watches directory (existing)
        ▼
MissionExecutionQueue.dispatch(.emailFile)   (existing)
        │
        │  "Mailing List Processor" mission fires
        ▼
incoming_email_trigger → write_action_item
        │
        ▼
iOS Actions tab (calendar.create, url.open, reminder.add, …)
```

No Rails changes. No iOS changes. The IMAP poller slots into the existing
email pipeline at the inbox directory boundary.

---

## One-time setup

### 1. Gmail relay account

Create a new private Gmail address — for example `familykvtagent.relay@gmail.com`.
This address is never shared with anyone; it only exists so the agent can read via IMAP.

Enable IMAP:
- Gmail Settings → See all settings → Forwarding and POP/IMAP → Enable IMAP → Save

Generate an app password:
- Google Account → Security → 2-Step Verification → App passwords
- App: "AgentKVT" (or any label)
- Copy the 16-character password — you'll need it below

### 2. Tuta forwarding rule

In Tuta (`familykvtagent@tuta.com`):
- Settings → Inbox rules → Add rule
- Condition: "All messages"
- Action: Forward to `familykvtagent.relay@gmail.com`

Verify by sending a test email to the Tuta address and confirming it arrives in Gmail.

### 3. Configure the agent

Add these keys to `~/.agentkvt/agentkvt-runner.plist` on the server Mac:

```xml
<key>AGENTKVT_IMAP_HOST</key>
<string>imap.gmail.com</string>

<key>AGENTKVT_IMAP_PORT</key>
<integer>993</integer>

<key>AGENTKVT_IMAP_USERNAME</key>
<string>familykvtagent.relay@gmail.com</string>

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

Restart the Mac app (or the launchd service) to pick up the new config:

```bash
launchctl kickstart -k gui/$(id -u)/com.agentkvt.api
```

### 4. Create the "Mailing List Processor" mission

Open the iOS app → Missions → +

| Field | Value |
|-------|-------|
| Name | Mailing List Processor |
| Schedule | webhook |
| Allowed tools | `incoming_email_trigger`, `write_action_item` |

System prompt:

```
You process incoming mailing list and newsletter emails.

Call incoming_email_trigger to read the next email.

From the email content, extract the most useful items and call write_action_item for each:
- Events or deadlines → system_intent: "calendar.create" with date/time
- Links or articles worth reading → system_intent: "url.open" with the URL and a short label
- Reminders or follow-ups → system_intent: "reminder.add" with due date if mentioned

Write at most 3 action items per email. Prefer specific, actionable items over vague summaries.
If the email is pure promotional noise with no actionable content, do not write any action items.
```

---

## Config reference

| Key | Default | Description |
|-----|---------|-------------|
| `AGENTKVT_IMAP_HOST` | — | IMAP server hostname (required) |
| `AGENTKVT_IMAP_PORT` | `993` | IMAP SSL port |
| `AGENTKVT_IMAP_USERNAME` | — | IMAP login username (required) |
| `AGENTKVT_IMAP_PASSWORD` | — | IMAP password or app password (required) |
| `AGENTKVT_IMAP_MAILBOX` | `INBOX` | Mailbox to poll |
| `AGENTKVT_IMAP_POLL_SECONDS` | `300` | Poll interval in seconds (minimum 60) |

The poller is disabled unless all three required keys (`HOST`, `USERNAME`, `PASSWORD`) are set.

---

## How it works

`IMAPEmailPoller` is a Swift actor that fires on a repeating timer. On each tick it runs
`~/.agentkvt/imap_fetch.py` (written to disk on first use) via `/usr/bin/python3`.

The script:
1. Connects to the IMAP server over SSL
2. Searches for `UNSEEN` messages
3. Fetches each message body (`RFC822`) — this marks them as read on the server
4. Writes each message to `~/.agentkvt/inbox/imap-{id}-{timestamp}.eml`
5. Returns a JSON array of written paths

`EmailIngestor` watches the inbox directory and enqueues each `.eml` for the
`incoming_email_trigger` tool. The Mailing List Processor mission fires, reads the email,
and writes action items. No additional configuration needed after the initial setup.

---

## Verification

**1. Smoke-test IMAP credentials directly:**

```bash
python3 ~/.agentkvt/imap_fetch.py \
  imap.gmail.com 993 \
  familykvtagent.relay@gmail.com "app password" \
  INBOX ~/.agentkvt/inbox
```

Should print `[]` (no unseen messages) or a JSON array of written `.eml` paths.

**2. End-to-end test:**

Send an email to `familykvtagent@tuta.com` from an external address.
Within ~5 minutes, a `.eml` file should appear in `~/.agentkvt/inbox/`.

Tail the log to confirm dispatch:

```bash
tail -f ~/.agentkvt/logs/agentkvt-mac.log | grep -E "IMAP|emailFile"
```

**3. iOS confirmation:**

Action items from the processed email appear in the iOS Actions tab within one poll cycle.

**4. Mark-read check:**

In the Gmail relay inbox, processed messages should appear as read (not bold).
