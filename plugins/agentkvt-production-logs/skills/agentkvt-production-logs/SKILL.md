---
name: agentkvt-production-logs
description: Pull and analyze live AgentKVT production logs from familyagent@192.168.4.144 using the repo-local production log analyzer. Use when the user asks for production logs, current production failures, or operational health on the production host.
---

# AgentKVT Production Logs

## Overview

Use this skill to inspect the live AgentKVT production environment over SSH.

- Prefer the plugin wrapper script `../../scripts/analyze_production_logs.sh`.
- The wrapper delegates to the repo-local analyzer at `bin/analyze_production_logs.sh`.
- By default it targets `familyagent@192.168.4.144`.

## Default Workflow

1. Run the wrapper with no arguments for the current summary.
2. Add `--raw` when the user wants raw log excerpts after the summary.
3. Add `--host <ssh-target>` only if the user explicitly wants a different server.
4. If SSH is blocked by the sandbox, rerun the command with escalated permissions.
5. Summarize the highest-signal failures with timestamps and likely causes.

## Command Forms

```bash
../../scripts/analyze_production_logs.sh
../../scripts/analyze_production_logs.sh --raw
../../scripts/analyze_production_logs.sh --host familyagent@192.168.4.144
```

## Interpretation Guide

- `No route matches [GET] "/v1/agent/missions/:id/action_items"` usually means the Rails server is stale or did not reload the latest routes.
- `422` with `Content can't be blank` for `assistant_final` or `outcome` means the runner emitted an empty final log payload.
- `WebhookListener error: Address already in use` usually means duplicate app instances or scheduler collisions.
- `_LSOpenURLsWithCompletionHandler() failed` in launchd stderr means the macOS app relaunch path is unstable.
- `cached plan must not change result type` in Postgres usually points to prepared statements surviving a schema change.

## Output Expectations

- Start with whether the stack is up: app, Rails API, Ollama, and `/healthz`.
- List the dominant failure classes in severity order.
- Include concrete timestamps and the affected route, mission, or process when available.
- If the analyzer output suggests a stale deploy or process mismatch, say so plainly.
