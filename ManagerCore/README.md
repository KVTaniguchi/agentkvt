# ManagerCore

Shared SwiftData schema and entities for the AgentKVT system (Brain on macOS, Remote on iOS).

## Contents

### Core Entities
- **LifeContext** — Static facts and user preferences.
- **ActionItem** — Dynamic button data for the iOS dashboard.
- **AgentLog** — Append-only audit log of agent reasoning and tool use.
- **FamilyMember** — In-app identity for family attribution.

### Chat
- **ChatThread** — Conversation thread with status tracking.
- **ChatMessage** — Individual messages within a chat thread.

### Research & Work
- **WorkUnit** — Stigmergy board task tracking.
- **EphemeralPin** — TTL-based ephemeral notes.
- **ResourceHealth** — Cooldown/backoff tracking for external resources.
- **ResearchSnapshot** — Persisted research findings (local delta tracking).
- **InboundFile** — Uploaded file tracking.

### Ingestion
- **IncomingEmailSummary** — Pre-summarized emails from the CloudKit bridge.

### Legacy
- **~~MissionDefinition~~** — *(Deprecated)* Superseded by server-side Objectives.

See [SCHEMA.md](SCHEMA.md) for full schema documentation.

## Requirements

- iOS 17+ / macOS 14+
- Swift 5.9+

## Usage

Add ManagerCore as a local dependency to your Mac and iOS app targets. Create a `ModelContainer` with the schema (see SCHEMA.md) and use the same container in both apps for local storage.

## Sync

The canonical sync strategy uses a Rails API backend. See `Docs/SYNC.md` for details.
