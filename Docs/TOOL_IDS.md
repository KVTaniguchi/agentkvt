# MCP Tool IDs

Use these IDs when configuring which tools a task or objective is authorized to use. Principle of least privilege: only include the tools each job needs.

## Core Tools

| Tool ID | Description |
|---------|-------------|
| `write_objective_snapshot` | Persist research findings (prose) for an objective task to the Rails backend. |
| `read_objective_snapshot` | Read existing research snapshots for an objective/task from the Rails backend. |

## Search & Research Tools

| Tool ID | Description |
|---------|-------------|
| `web_search_and_fetch` | Uses Ollama's web_search and web_fetch APIs; returns clean Markdown to the LLM. Requires `OLLAMA_API_KEY`. |
| `multi_step_search` | Runs 2–5 related queries in one turn (e.g. compare hotel prices across 3 sites). Each step can be `search` or `browse`. |
| `headless_browser_scout` | Loads a URL in headless WebKit; optional click/fill actions; returns page text. For JS-heavy sites. |
| `read_research_snapshot` | Read the last tracked value for a key (local delta tracking for repeating research). |
| `write_research_snapshot` | Persist a current value and detect meaningful change (local delta tracking). |

## Context & Data Tools

| Tool ID | Description |
|---------|-------------|
| `get_life_context` | Read LifeContext entries (goals, location, preferences) from local SwiftData. |
| `fetch_agent_logs` | Read recent agent logs. Filter by mission_name or phases. |
| `fetch_bee_ai_context` | Fetch personal context from [Bee Computer](https://docs.bee.computer/docs) via local `bee proxy`. See [BEE_AI_INTEGRATION_PLAN.md](BEE_AI_INTEGRATION_PLAN.md). |
| `github_agent` | Read-only GitHub operations on allowed repositories (list issues). PAT and repo allowlist configured at startup. |

## Communication Tools

| Tool ID | Description |
|---------|-------------|
| `send_notification_email` | Send a notification email to the user. Destination is fixed (env/keychain); only subject and body from LLM. |
| `incoming_email_trigger` | Get next pending email from Agent Inbox (intent + sanitized content; PII stripped). See [EMAIL_INGESTION.md](EMAIL_INGESTION.md). |

## File & Dropzone Tools

| Tool ID | Description |
|---------|-------------|
| `list_dropzone_files` | List files in the inbound dropzone directory. |
| `read_dropzone_file` | Read a specific file from the dropzone. |

## Stigmergy Board Tools

| Tool ID | Description |
|---------|-------------|
| `fetch_work_units` | Read work units by state/category from the stigmergy board. |
| `update_work_unit` | Update state/payload/phase on a work unit. |
| `pin_ephemeral_note` | Write a short-lived pin with TTL. |
| `list_resource_health` | List resource health/cooldown entries. |
| `report_resource_failure` | Record a resource failure for backoff/cooldown. |
| `clear_resource_health` | Clear a resource health entry. |

---

## Runtime Behavior

The Mac runner automatically appends runtime guidance for each tool in a task's allowed list, helping the model understand when and how to use each tool effectively. Tool guidance is generated dynamically based on the task's system prompt and allowed tool IDs.
