# ManagerCore

Shared SwiftData schema and entities for the AgentKVT system (Brain on macOS, Remote on iOS).

## Contents

- **LifeContext** — Static facts and user preferences.
- **MissionDefinition** — User-defined mission config (name, prompt, schedule, allowed tools).
- **ActionItem** — Dynamic button data for the iOS dashboard.
- **AgentLog** — Append-only audit log of agent reasoning and tool use.

See [SCHEMA.md](SCHEMA.md) for full schema documentation.

## Requirements

- iOS 17+ / macOS 14+
- Swift 5.9+

## Usage

Add ManagerCore as a local or remote dependency to your Mac and iOS app targets. Create a `ModelContainer` with the schema (see SCHEMA.md) and use the same container (or synced store) in both apps.

## Sync

Sync strategy (CloudKit vs local network) is documented in the repo at `Docs/SYNC.md`.
