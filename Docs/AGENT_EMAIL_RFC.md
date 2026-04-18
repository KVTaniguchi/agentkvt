# Agent Email RFC

Status: Draft  
Date: April 17, 2026

## Purpose

Agent email is sovereignty infrastructure.

The goal is not merely to let AgentKVT read the user's mail. The goal is to give
AgentKVT a durable digital identity that can act as a bounded proxy for the
household, similar to how a family-office manager uses a separate office address
to interface with vendors, clinics, schools, and logistics providers.

This RFC defines a concrete v1 architecture for:

- agent-specific email addresses
- safe inbound mail access on the Mac runner
- iOS policy controls for what each address is allowed to do
- a staged pipeline that turns email into reviewed context and action signals

Use alongside [EMAIL_INGESTION.md](EMAIL_INGESTION.md),
[EXECUTION_ROADMAP.md](EXECUTION_ROADMAP.md), and
[SOVEREIGN_PLANNER_VISION.md](SOVEREIGN_PLANNER_VISION.md).

## Recommendation

The selected platform is AgentMail.

Phase 1 should use AgentMail as the inbox and sending platform, with AgentKVT
holding one or more agent-owned inboxes while preserving local safety controls
on the Mac.

The recommended operating model is still the "Alias Hive":

- one AgentMail-backed inbox or family of inboxes is connected to the Mac runner
- agent-specific addresses can be created directly in AgentMail or mapped to
  role-specific identities in AgentKVT
- the runner routes inbound mail by inbox identity rather than by scraping a
  personal mailbox

Examples:

- `agent+shopping@taniguchi.dev`
- `agent+health@taniguchi.dev`
- `agent+travel@taniguchi.dev`

Tuta should not be the primary provider for machine access in v1. As of April
17, 2026, Tuta still does not expose standard IMAP/POP access, which makes it a
poor fit for the current Mac-side IMAP foundation and would push AgentKVT toward
fragile browser automation.

## Why Now

Email is still the default control surface for the real world. Vendors,
healthcare offices, delivery services, schools, utilities, and banks all emit
their operational state through email first.

If AgentKVT can:

- hold its own address
- safely inspect mail sent to that address
- extract logistics signals without treating email as executable instruction
- surface trusted changes back to iPhone

then AgentKVT starts behaving less like a chat assistant and more like a true
household operations proxy.

## Existing Foundation In Repo

The repo already contains several pieces we should build on instead of replacing:

- [AgentKVTMac/Sources/AgentKVTMac/IMAPEmailPoller.swift](../AgentKVTMac/Sources/AgentKVTMac/IMAPEmailPoller.swift)
  can already poll an IMAP mailbox and write raw `.eml` files to the local inbox.
- [AgentKVTMac/Sources/AgentKVTMac/EmailIngestor.swift](../AgentKVTMac/Sources/AgentKVTMac/EmailIngestor.swift)
  already watches the inbox and creates a pending email queue.
- [AgentKVTMac/Sources/AgentKVTMac/EmailSanitizer.swift](../AgentKVTMac/Sources/AgentKVTMac/EmailSanitizer.swift)
  already strips some sensitive patterns before model exposure.
- [server/db/migrate/20260410120000_create_hands_foundation.rb](../server/db/migrate/20260410120000_create_hands_foundation.rb)
  already introduced `agent_identities`, `agent_personas`, and
  `workspace_provider_credentials`.
- [server/app/models/slack_message.rb](../server/app/models/slack_message.rb)
  already has the concept of `trust_tier`, which is a useful precedent for email.
- [server/app/models/research_snapshot.rb](../server/app/models/research_snapshot.rb)
  already supports `is_repellent`, `repellent_reason`, and `snapshot_kind`,
  which can be reused for quarantined email-derived signals.
- [server/app/controllers/v1/inbound_files_controller.rb](../server/app/controllers/v1/inbound_files_controller.rb)
  and
  [server/app/controllers/v1/agent/inbound_files_controller.rb](../server/app/controllers/v1/agent/inbound_files_controller.rb)
  already give us a safe pattern for moving sensitive binary content through the
  system.

## Product Principles

### 1. Email is identity plus policy

An agent address is not only a transport endpoint. It also carries:

- a public identity
- an allowed purpose
- a safety tier
- a bounded capability set

### 2. Email is context candidate, not instruction

Inbound email must not be treated as trusted imperative input. The pipeline
should produce a candidate signal that can become:

- an `ActionItem`
- a `ResearchSnapshot`
- a notification
- a queued draft

but never a blind direct command.

### 3. Raw mail stays local by default

The raw MIME payload should remain on the Mac in Phase 1. The server should
store only a structured sanitized projection plus audit metadata.

### 4. One mailbox credential, many public addresses

The system should prefer alias routing over many standalone mailboxes. This
reduces credential sprawl while preserving agent-specific identities.

## Goals

- Allow the iOS client to define agent-owned email identities.
- Allow the Mac runner to access the backing mailbox with one connector.
- Route inbound mail by delivered alias.
- Safely classify and sanitize email before any model sees it.
- Turn useful messages into structured outputs visible on iOS.
- Prevent high-risk classes of mail from being handled autonomously.

## Non-Goals For Phase 1

- autonomous purchasing
- autonomous reply sending
- browser-session mail access
- direct handling of bank alerts, password resets, MFA codes, or legal notices
- a full end-user auth redesign for the Rails API

## Proposed Architecture

### Top-Level Model

There are three layers:

1. `Agent Identity`
   A public address and persona, such as `agent+health@taniguchi.dev`.

2. `Access Connector`
   The technical mechanism the Mac uses to read the underlying mailbox, such as
   IMAP in Phase 1.

3. `Safety Policy`
   The rules that decide what the agent may do with mail sent to that identity.

### Alias Hive

Recommended provider setup:

- AgentMail account with API key
- one or more AgentMail inboxes dedicated to AgentKVT
- optional workspace-level routing that maps inboxes to role-specific identities

Conceptually:

```text
agent@taniguchi.dev
  -> agent+shopping@taniguchi.dev
  -> agent+health@taniguchi.dev
  -> agent+travel@taniguchi.dev
```

The Mac runner connects once via IMAP, reads each message, extracts the
delivered alias from `To`, `Delivered-To`, or other routing headers, and maps
the message to the configured identity.

## Data Model

### Keep

- `agent_identities`
  Keep as the workspace-level default public identity for AgentKVT.

- `agent_personas`
  Keep for channel-specific presentation and tone.

- `workspace_provider_credentials`
  Keep for provider metadata, but do not use it for raw IMAP secrets in Phase 1.

### Add

#### `agent_email_identities`

New table for per-address policy and routing.

Suggested fields:

- `workspace_id: uuid`
- `slug: string`
- `address: string`
- `display_name: string`
- `purpose: text`
- `capability_mask: integer`
- `safety_tier: string`
- `trusted_domains: string[]`
- `trusted_senders: string[]`
- `status: string`
- `metadata_json: jsonb`
- timestamps

Suggested enums:

- `safety_tier`: `trusted_vendors_only`, `known_people_and_vendors`,
  `manual_review_required`
- `status`: `active`, `paused`, `quarantined`

Suggested capability bits:

- `read_summarize`
- `detect_tracking`
- `create_context_candidate`
- `create_action_item`
- `draft_reply`
- `send_reply`

`send_reply` should remain disabled in Phase 1 and locked in the iOS UI.

#### `agent_email_messages`

New table for sanitized projections of inbound email.

Suggested fields:

- `workspace_id: uuid`
- `agent_email_identity_id: uuid`
- `provider_message_id: string`
- `direction: string`
- `source_connector: string`
- `to_address: string`
- `from_address: string`
- `subject: string`
- `received_at: datetime`
- `trust_tier: string`
- `risk_label: string`
- `risk_flags: jsonb`
- `auth_results_json: jsonb`
- `sanitized_body: text`
- `sanitized_summary: text`
- `raw_mime_sha256: string`
- `is_quarantined: boolean`
- `is_processed: boolean`
- `processed_at: datetime`
- `metadata_json: jsonb`
- timestamps

This record is the server-side audit unit for email, not the raw `.eml`.

#### `agent_email_connector_states`

Optional but useful for observability.

Suggested fields:

- `workspace_id: uuid`
- `connector_type: string`
- `status: string`
- `last_success_at: datetime`
- `last_error_at: datetime`
- `last_error_message: text`
- `metadata_json: jsonb`

## Provider Credential Strategy

Phase 1 should split policy from secrets:

- iOS configures identity and policy through the Rails API
- the Mac stores the actual IMAP credential in the local runner plist or Keychain
- the server stores only connector metadata and capability state

This is important because the current Rails API does not yet have robust
end-user authentication on workspace-facing endpoints. Sensitive mailbox secrets
should not be added to server-managed user-facing API writes until auth is
hardened.

`workspace_provider_credentials` should be extended to recognize email-related
provider types such as:

- `email_imap`
- `email_inbound_webhook`
- `email_outbound_api`

but `secret_value` should remain metadata-only for this feature until secret
storage is encrypted and member-authenticated.

## iOS Product Surface

Add a new screen: `Agent Email`.

This should behave like an infrastructure editor, not a casual settings page.

### Identity Card

- Address
- Display name
- Purpose
- Status
- Last message seen
- Connector health

### Capability Controls

- `Read / Summarize`
- `Detect Tracking Numbers`
- `Create Action Items`
- `Create Context Candidates`
- `Draft Replies` (Phase 2)
- `Auto-Send Replies` (Phase 3, locked)

### Safety Policy

- Safety tier selector
- Trusted domains
- Trusted senders
- Attachment handling policy
- High-risk category toggles

### Example

- Identity: `agent+shopping@taniguchi.dev`
- Purpose: `Handles basics procurement and delivery tracking.`
- Capabilities:
  - `Read / Summarize`: on
  - `Detect Tracking Numbers`: on
  - `Draft Replies`: off
  - `Auto-Send Replies`: locked
- Safety tier: `Trusted Vendors Only`
- Trusted domains:
  - `amazon.com`
  - `target.com`

## API Surface

Add new workspace-facing endpoints:

- `GET /v1/agent_email/identities`
- `POST /v1/agent_email/identities`
- `PATCH /v1/agent_email/identities/:id`
- `GET /v1/agent_email/messages`
- `GET /v1/agent_email/messages/:id`
- `POST /v1/agent_email/messages/:id/quarantine`
- `POST /v1/agent_email/messages/:id/release`

Add new agent-facing endpoints:

- `POST /v1/agent/email_messages`
  The Mac posts a sanitized projection after local parsing and classification.
- `POST /v1/agent/email_messages/:id/mark_processed`
- `POST /v1/agent/email_connector/status`

The bootstrap payload should eventually include email identities and connector
health so iOS can render this screen without extra setup steps.

## Mac Runner Changes

### 1. Keep `IMAPEmailPoller`, but make it alias-aware

The current poller is a strong foundation and should remain the Phase 1 ingress
mechanism.

Required upgrades:

- preserve relevant headers, not just subject and body
- parse `To`, `Delivered-To`, and sender information
- compute a message fingerprint and raw MIME hash
- hand the message to an alias router before it reaches the LLM

### 2. Replace bare `EmailIngestor` output with structured ingress

Today `EmailIngestor` effectively returns:

- intent
- sanitized general content

That is too lossy for sovereign email operations.

It should evolve into a pipeline like:

1. parse MIME
2. strip HTML and tracking pixels
3. extract canonical plain text
4. extract addresses, headers, and attachment metadata
5. route to `agent_email_identity`
6. run risk classification
7. persist sanitized projection to the backend
8. enqueue analysis only if policy allows

### 3. Do not overload objective `Task` for every email

The current server `Task` model is objective-scoped. Using it for all inbound
email would pollute the objective system with operational mail traffic.

Instead, Phase 1 should use one of these patterns:

- a dedicated `AgentExecutionQueue` trigger for email analysis
- a lightweight email-analysis job record
- a `WorkUnit`-style queue if we want durable claim/complete semantics

This is the closest equivalent to "create a task automatically" without bending
the objective system out of shape.

### 4. Add `AgentEmailClassifier`

Run a small local classifier before any autonomous downstream behavior.

Suggested labels:

- `tracking_update`
- `receipt`
- `appointment_change`
- `vendor_alert`
- `newsletter`
- `spam`
- `high_risk_security`
- `high_risk_financial`
- `high_risk_legal`
- `medical_sensitive`

Suggested outputs:

- label
- trust tier
- risk flags
- summary
- recommended action

## Safety Pipeline

Email should follow a stricter variant of the existing ingestion philosophy.

### Stage 1: Ingress

The Mac fetches MIME from IMAP.

Equivalent: sensing the wind.

### Stage 2: Sanitization

The Mac strips:

- HTML noise
- tracking pixels
- obvious trackers and unsubscribe junk
- known sensitive tokens
- phone numbers, IDs, and account-like sequences

Equivalent: filtering toxins.

### Stage 3: Classification

A local classifier determines what kind of email this is and how dangerous it is.

Equivalent: olfactory analysis.

### Stage 4: The Mark

The system writes a structured sanitized artifact, typically:

- `agent_email_messages` row
- `ResearchSnapshot` with `source=email`
- possibly `is_repellent=true` when the content must not be acted on autonomously

Equivalent: dropping a pheromone.

### Stage 5: The Reflex

The iPhone or backend reacts by creating:

- an `ActionItem`
- a push notification
- a visible review request

Equivalent: the hive reacts.

## High-Risk Quarantine Rules

The following categories should be quarantined by default in Phase 1:

- password reset emails
- MFA / OTP codes
- bank alerts
- tax documents
- legal notices
- medical results
- payroll or benefits changes
- any message with executable attachments
- any message whose sender fails configured trust policy

Quarantined mail should:

- be persisted as a sanitized audit record
- optionally emit a repellent `ResearchSnapshot`
- never be used as autonomous instruction
- never trigger automatic outbound action

## Trusted Vendor Policy

`Trusted Vendors Only` should mean more than a plain domain allowlist.

Recommended checks:

- sender domain is allowlisted
- where available, SPF/DKIM/DMARC or equivalent auth results are acceptable
- no high-risk classifier hit
- no dangerous attachment type
- message category is in a permitted class for that identity

If any check fails, the message downgrades to manual review.

## Outbound Policy

Phase 1 is inbound-only plus internal reaction.

Phase 2 may support `draft_reply`.

Phase 3 may support `send_reply`, but only with all of the following:

- explicit per-identity enablement
- approved provider connector for sending
- reply template policy
- human-review option
- complete audit trail

`send_reply` must not piggyback on the current `send_notification_email` tool,
which is intentionally fixed-destination and exists for a different safety model.

## Recommended Phase Plan

### Phase 1: The Observer

Outcome:

- AgentKVT owns email identities.
- AgentKVT reads inbound mail safely.
- AgentKVT turns trusted operational emails into summaries, snapshots, and
  action items.

Build:

- `agent_email_identities`
- `agent_email_messages`
- iOS `Agent Email` screen
- alias-aware IMAP ingress
- risk classifier
- quarantine rules
- `source=email` research snapshot path
- action-item creation for trusted classes like tracking or schedule changes

### Phase 2: The Drafting Proxy

Outcome:

- AgentKVT can prepare replies but not send them automatically.

Build:

- draft-reply capability
- outbound connector abstraction
- iOS review and approve flow

### Phase 3: The Bounded Proxy

Outcome:

- AgentKVT can send narrow, policy-bound outbound replies for certain identities.

Build:

- locked `send_reply`
- approval rules
- per-identity reply scope
- stronger auth and secret management

## Concrete Example

Scenario:

1. `agent+health@taniguchi.dev` receives `Holiday Hours: Closed Monday`.
2. The Mac runner fetches the MIME via IMAP.
3. The alias router maps it to the `health` identity.
4. The classifier labels it `appointment_change` with medium risk and high trust.
5. The system writes an `agent_email_messages` record and a `ResearchSnapshot`
   sourced from email.
6. The backend or iOS derives an `ActionItem` or notification:
   `Allergist emailed: closed Monday. Plan accordingly.`

This is the smallest believable family-office loop.

## Risks

### 1. Current workspace auth is too weak for secret management

Today workspace-facing endpoints are selected by `X-Workspace-Slug`. That is not
enough for mailbox credential management. Phase 1 avoids this by keeping IMAP
secrets local to the Mac.

### 2. The current email sanitizer is too light for sovereign email

Regex-only redaction is a good start but not sufficient for broad real-world
mail. HTML cleanup, header parsing, tracker stripping, and better entity
classification are required.

### 3. Alias semantics differ by provider

The product should be designed around alias routing, but implementation should
avoid assuming one exact provider-specific pattern until the mailbox setup is
confirmed in production.

### 4. Objective and operational pipelines should stay separate

Operational email handling should not degrade the objective system by turning
every vendor message into an objective task.

## Open Questions

1. Should email-derived `ActionItem` creation happen on the Mac immediately, or
   should the backend create it from the persisted `agent_email_messages` row?
2. Should sanitized email excerpts be stored in Postgres in full, or only as a
   capped summary plus hash?
3. Should trusted-domain policy live only on the identity row, or also support
   reusable workspace-level allowlists?
4. Should the alias router prefer `Delivered-To`, `X-Original-To`, or `To` when
   providers rewrite headers?
5. When user auth is strengthened, should IMAP secrets move into encrypted
   server storage or stay Mac-local permanently?

## Immediate Implementation Recommendation

Implement Phase 1 in this order:

1. Add `agent_email_identities` and `agent_email_messages`.
2. Add iOS CRUD for identity and policy.
3. Upgrade the Mac ingest path to parse alias and headers before model exposure.
4. Add the classifier and quarantine path.
5. Persist sanitized email records to Rails.
6. Emit `ResearchSnapshot` and `ActionItem` only for allowed low-risk classes.

This gives AgentKVT a real digital footprint without pretending that inbound
email is safe by default.
