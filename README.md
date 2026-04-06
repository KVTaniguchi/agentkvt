<div align="center">

# 🧠 AgentKVT

**Your Family's Localized, Closed-Loop Agentic System**  
*Mac Brain · iOS Remote · Rails + Postgres Backend*

---

🚧 **IN PROGRESS** 🚧  
**This project is under active development. APIs, schema, and behavior may change.**

</div>

## Overview

AgentKVT is a sovereign, self-hosted personal agent ecosystem. It operates entirely on your own hardware, ensuring your family's data never leaves your environment. It is designed to act on **Objectives** (e.g. "Plan San Diego trip logistics") by decomposing them into tasks, executing multi-step research through an autonomous Mac-hosted brain, and surfacing actionable results directly to your iOS device.

By utilizing a central **Rails + PostgreSQL** backend on a Mac server instead of iCloud, multiple family members with different Apple IDs can seamlessly share a unified workspace.

## Core Architecture

AgentKVT consists of three cooperating layers:

1. **The Remote (iOS):** A SwiftUI dashboard running on your iPhone. It's backend-first—you create **Objectives** and review **ActionItems**, context, and logs by connecting to the Rails API (often over Tailscale). Real-time status chips show when the Mac agent is actively working.
2. **The API & Store (Server):** A Mac-hosted **Ruby on Rails** application exposing versioned HTTP endpoints. Postgres serves as the definitive, multi-device source of truth for workspaces, tasks, research snapshots, action items, and agent logs. 
3. **The Brain (macOS):** An event-driven macOS background application `ObjectiveExecutionPool` that pulls tasks from the Rails server. It runs an autonomous loop using local LLMs (via Ollama) and a registry of sandboxed MCP (Model Context Protocol) tools to conduct research and synthesis.

## How the Objectives Pipeline Works

*Note: This objectives-based pipeline completely replaces the legacy "Missions" engine.*

1. **Create an Objective:** A user adds a high-level goal in the iOS app.
2. **Task Planning:** The Rails backend breaks down the objective into actionable **Tasks** using LLM-assisted planning.
3. **Execution Delivery:** The Mac Brain continuously polls or receives webhooks from the server. It picks up pending tasks and dispatches them to worker threads.
4. **Agentic Loop:** The local LLM research engine runs multi-step tasks using over 20+ allowed system tools (secure browsing, file reading, semantic search, etc.).
5. **Results & Action Items:** Research findings are synced back to the Postgres database as **ResearchSnapshots** and presented natively in the iOS app. If the agent discovers a concrete next step (e.g., "Review Acme Corp Job Description" or "Approve Trip Budget"), an **ActionItem** is created.
6. **Transparency:** Every single step, tool call, and token metric is preserved as an **AgentLog** for a complete audit trail.

## Repository Structure

- **`ManagerCore/`** — Shared Swift package defining the SwiftData/Model schema (`Objective`, `Task`, `ActionItem`, `AgentLog`, `ChatThread`, etc.) used by both Mac and iOS clients.
- **`AgentKVTMac/`** — The macOS background agent app. Includes the event-driven scheduler, task runners, the sandboxed tool registry, and the Ollama client integration.
- **`AgentKVTiOS/`** — The iOS SwiftUI project. Features tabs for Objectives, Actions, Context, Log, Chat, and Files. 
- **`server/`** — The Ruby on Rails API. Provides the core PostgreSQL database, schema, and API controllers.
- **`Docs/`** — Extensive architectural guides, deployment instructions, and vision documents.

## Detailed Documentation

To dive deeper into the project, consult our comprehensive and freshly-consolidated documentation:

### 🏛 Architecture & Vision
- [FOUNDATIONAL_PLAN.MD](FOUNDATIONAL_PLAN.MD) — Overview of architecture, schema, sandboxing, and data flows.
- [Docs/SOVEREIGN_PLANNER_VISION.md](Docs/SOVEREIGN_PLANNER_VISION.md) — Product vision and north-star sovereign direction.
- [Docs/EXECUTION_ROADMAP.md](Docs/EXECUTION_ROADMAP.md) — MVP definitions, milestones, and near-term task execution priorities.
- [Docs/SUPERAGENT_IMPLEMENTATION_PHASES.md](Docs/SUPERAGENT_IMPLEMENTATION_PHASES.md) — Phased rollout plan, updated for the objectives-based pipeline.

### 📖 Reference & Engineering
- [Docs/DATA_FLOW.md](Docs/DATA_FLOW.md) — Detailed mapping of data flows (iOS → Rails → Mac Agents → iOS).
- [Docs/TOOL_IDS.md](Docs/TOOL_IDS.md) — Master list of the 20+ authorized MCP tool IDs used by the Mac Brain.
- [Docs/SYNC.md](Docs/SYNC.md) — Explanation of the backend-first, Postgres-authoritative sync model.
- [Docs/LLM_THROTTLING.md](Docs/LLM_THROTTLING.md) — Runtime guidelines for a dedicated machine.

### ⚙️ Operations & Deployment
- [Docs/DEPLOYMENT.md](Docs/DEPLOYMENT.md) — Consolidated guide for setting up the Server, Mac Brain, and iOS environments.
- [Docs/E2E_VERIFICATION.md](Docs/E2E_VERIFICATION.md) — End-to-end testing scenarios (including Career/Finance workflows) and checklists.

### 📥 Data Ingestion
- [Docs/EMAIL_INGESTION.md](Docs/EMAIL_INGESTION.md) — Handling IMAP email polling, sanitization, and the Agent Inbox.
- [Docs/DROPZONE.md](Docs/DROPZONE.md) — Secure, local file inbound directory tracking.
- [Docs/BEE_AI_INTEGRATION_PLAN.md](Docs/BEE_AI_INTEGRATION_PLAN.md) — Integration plan for utilizing Bee personal context over local HTTP.

## Quick Start

### 1. Build Shared Core
```bash
cd ManagerCore && swift build
```

### 2. Run Rails Server
Requires PostgreSQL. See the [Deployment Guide](Docs/DEPLOYMENT.md).
```bash
./bin/run_agentkvt_api.sh
```

### 3. Run Mac Brain
Requires [Ollama](https://ollama.ai) running on localhost.
```bash
# Event-driven background worker
cd AgentKVTMac && RUN_SCHEDULER=1 swift run AgentKVTMacRunner
```

### 4. Build iOS App
Open `AgentKVTiOS/AgentKVTiOS.xcodeproj` in Xcode. Set your Development Team in Xcode settings, build, and deploy to your device.

---

### Operations & Debugging

Analyze recent agent logs over SSH to see what your AI brain is up to:
```bash
./bin/analyze_agent_logs.sh
```
*(Tip: Set `AGENTKVT_PROD_HOST` to define your own server IP, or add `--raw` to view detailed sampled log excerpts.)*
