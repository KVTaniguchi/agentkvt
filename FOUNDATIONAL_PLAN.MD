1. System Architecture Overview

Build a localized, closed-loop agentic system consisting of three cooperating layers:

**The Brain (macOS):** A background-capable Mac app that acts as an MCP (Model Context Protocol) host and autonomous task runner. Inference is handled locally via an LLM host (e.g. Ollama). When a backend URL is configured, the runner loads missions from the API and writes agent logs and action items back through the same API so they land in **Postgres**. Without that URL, it can still operate against on-device **SwiftData** (development or offline-style paths).

**The API + database (Rails on the home server Mac):** A **Ruby on Rails** application in `server/` talks to **PostgreSQL**. It exposes versioned **HTTP JSON** endpoints under `/v1/…` (clients) and `/v1/agent/…` (agent token). This is the **shared source of truth** for workspaces, missions, action items, agent logs, life-context entries, and family members—**not** iCloud or a shared CloudKit container. Each person can use their own Apple ID on their devices; sync is **application-level** via your server, independent of iCloud account boundaries.

**The Remote (iOS):** A SwiftUI app on iPhone. It reads and writes the same domain data **through the Rails API** (base URL + workspace slug), then **reconciles** responses into local **SwiftData** (`ManagerCore`) for `@Query` and offline-friendly UI. Reachability from off-LAN is typically via **Tailscale** (MagicDNS or Tailscale IP) to the Mac that hosts Rails.

**The Bridge (cross-device sync):** **HTTPS/HTTP to the Rails API backed by Postgres.** There is no Core Data stack. Client-side persistence is **SwiftData** (Apple’s Swift-native model layer), which mirrors server state and powers tools/UI on each device; it is **not** the authoritative multi-device store—Postgres is.

---

2. Dedicated Machine Runtime Model (Critical Setup)

The macOS agent and the Rails API are intended to run on a **dedicated Apple Silicon Mac** used as the home “brain” machine—**not** tied to a specific product name (e.g. Mac Studio). That host runs the local LLM, the scheduler/runner, and the Postgres-backed API that phones and the same Mac use for shared state.

Runtime behavior should prioritize availability and predictable execution rather than preserving interactivity for unrelated foreground apps. The implementation should prevent unwanted sleep/App Nap, keep the runner stable during long reasoning loops, and avoid overlapping mission execution.

There is no requirement for an application-level CPU, GPU, or Neural Engine throttle in the agent itself. Resource management should come from operational choices such as model size, one mission at a time, bounded trigger queues, and LLM-host configuration where supported.

---

3. Data Stores: Postgres (server) and SwiftData (clients)

**PostgreSQL (authoritative, via Rails)**  
Rails models map to tables including, in broad strokes: `workspaces` (e.g. slugged workspace, `server_mode` such as single-mac-brain), `users`, `workspace_memberships`, `missions`, `action_items`, `agent_logs`, `life_context_entries`, `family_members`, `devices`. The schema lives in `server/db/schema.rb`; API routes in `server/config/routes.rb` (`v1` resources plus `v1/agent/*` for the Mac agent token).

**ManagerCore + SwiftData (on each Mac / iPhone)**  
The shared Swift package **ManagerCore** defines `@Model` types (`LifeContext`, `MissionDefinition`, `ActionItem`, `AgentLog`, chat models, etc.) used by SwiftUI and the runner. Clients **insert/fetch/update** through `ModelContext` for responsiveness and features that are still local-first; when the backend is enabled, **iOS** (`IOSBackendAPIClient`) and **Mac** (`BackendAPIClient`) **push/pull JSON** so Postgres and local SwiftData stay aligned for the API-covered entities.

Conceptual rule: **Postgres + Rails = system of record for shared, multi-device data; SwiftData = per-device projection and local-only concerns.**

---

4. Agent Sandboxing & MCP Tool Guardrails

To prevent destructive actions during autonomous loops, implement strict boundaries in the MCP Server layer. All tools must be built with "Zero Trust" principles regarding the LLM's output.

The "Only Me" Notification Tool: Create a Swift tool called sendNotificationEmail. Hardcode the destination email address (the user's address) directly into the compiled function or secure keychain. Expose only subject and body parameters to the LLM. It must be physically impossible for the agent to email external addresses.

Restricted Version Control Tool: Create a GitHub MCP tool. It must authenticate using a dedicated Bot Personal Access Token (PAT). This token configuration must enforce scoping exclusively to designated agent-accessible repositories, completely isolating the user's primary GitHub profile and private codebases.

---

5. Core Autonomous Missions (Dynamic Mission Engine)

Do not hardcode specific user tasks. Instead, build a Dynamic Mission Engine that allows the user to define, schedule, and execute custom background loops. The macOS service acts as a runner that processes these user-defined missions—loading definitions from the **backend API** when configured, otherwise from local SwiftData.

A. The MissionDefinition Schema

Users construct their own agents from the iOS interface. The entity must include:

- **missionName:** String identifier (e.g., "Tech Job Scout", "Budget Sentinel").
- **systemPrompt:** The user-defined instructions for the LLM (e.g., "Search for iOS roles within 15 miles and calculate the commute.").
- **triggerSchedule:** How often the Mac agent runs this loop (e.g., Daily at 8 AM, Weekly, or Triggered by a webhook/external event).
- **allowedMCPTools:** An array of tool IDs this specific mission is authorized to use (e.g., [web_scraper, maps_api, pdf_generator]), ensuring the principle of least privilege.

B. The Mac Execution Loop

The background macOS app runs a scheduler that obtains **due missions** (via `GET` to the agent API when the backend is configured, or from SwiftData otherwise), passes **systemPrompt** and **allowedMCPTools** to the local LLM, executes tools in the sandbox, and persists results—**action items and logs**—via **POST** to Rails when `BackendAPIClient` is active, or into SwiftData when not.

Output: Regardless of the custom mission, the output must always be standardized. The agent writes results so the iOS dashboard can show **ActionItem** rows (dynamic buttons) and audit **AgentLog** entries—stored in Postgres when the API path is used.

C. Example Implementation (For Testing Purposes Only)

To verify the engine works, the developer will input the following test missions via the UI, but they must not be hardcoded into the compiled binary:

- **Test Mission 1 (Career):** A prompt instructing the agent to scan job boards and cross-reference a local resume file, generating an ActionItem for high-match roles.
- **Test Mission 2 (Finance):** A prompt instructing the agent to monitor specific CSV transaction exports for impulse purchases, generating an ActionItem for manual review if limits are exceeded.

---

6. Personal memory bridge ([Bee](https://docs.bee.computer/docs))

[Bee](https://docs.bee.computer/) (bee.computer) is an optional **external personal context** source: conversations, facts, todos, daily summaries, and search—exposed to developers via the **Bee CLI** (`bee login`, `bee now`, `bee sync`, etc.) and, for programmatic access, a **`bee proxy` local HTTP server** that forwards **`/v1/*`** routes (see [API / proxy](https://docs.bee.computer/docs/proxy)). The Mac agent’s **`fetch_bee_ai_context`** tool is intended to pull summarized context from that surface (or a Bee-compatible base URL) into **LifeContext** / **AgentLog** so missions can ground on recent life notes without duplicating Bee’s storage in Postgres.

Operational notes:

- Bee requires the **Bee iOS app** and **Developer Mode** (tap app Version five times); see Bee’s [Getting Started](https://docs.bee.computer/docs).
- For integrations that speak HTTP, the documented path is usually **`bee proxy`** on the Mac (default port **8787** in Bee’s docs) so AgentKVT calls `http://127.0.0.1:<port>/v1/...` rather than exposing the proxy publicly.
- Bee also documents **direct HTTPS** to their API with a **Bearer token** and a **private CA** (`bee-ca.pem`); clients must pin or trust that CA—see the same proxy/API page.

This does not change the core rule: **Postgres + Rails remain authoritative for AgentKVT missions and family data**; Bee is a **read-mostly enrichment** channel the runner can summarize into local state for the LLM.

---

## Architecture Diagram (current)

```text
[ USER ]
    |
    v
+------------------+       HTTP (JSON)        +------------------------+
|  iOS App         | -----------------------> |  Rails API (:3000)     |
|  SwiftUI +       |       Tailscale/LAN      |  (server/)             |
|  SwiftData cache | <----------------------- |                        |
+------------------+                         +------------+-------------+
                                                      |
                                                      | Active Record
                                                      v
                                           +------------------------+
                                           |  PostgreSQL            |
                                           |  (missions, logs,      |
                                           |   action items, …)     |
                                           +------------------------+
                                                      ^
                                                      |
+------------------+       HTTP (agent token)         |
|  Mac Brain       | --------------------------------+
|  Runner + MCP    |
|  + local SwiftData|       Local IPC
|  + Ollama        | <------> LLM inference
+------------------+
```

Flow summary:

1. **User** enters concerns or configures missions in the **iOS** app; writes go to **Rails**, which persists to **Postgres**. iOS refreshes local **SwiftData** from API responses.
2. **Mac runner** pulls work from the **same API** (and runs the LLM locally). It posts **agent logs** and **action items** to Rails; **iOS** pulls those via the same API—**no shared iCloud container** required across personal Apple IDs.
3. **Tailscale** (or LAN) provides a stable private path from phone to the Mac’s API URL; it does not replace HTTP—transport is still **REST**, not WebSockets, in the current codebase.
