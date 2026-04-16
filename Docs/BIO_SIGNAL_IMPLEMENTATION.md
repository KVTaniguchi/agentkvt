# Bio-Signal Intelligence: Implementation Plan

**Status:** Planned Roadmap  
**Scope:** Architecture evolution from uniform execution to a self-regulating, resource-aware agent ecosystem.

This document serves as the technical implementation roadmap for the Bio-Signal Intelligence strategy in AgentKVT. It targets four critical areas to transition the agentic execution model toward biological-inspired feedback loops: Negative Feedback (Repellents), Nutrient-Density Scoring, Dynamic Resource Allocation, and Environmental Priming (Exudates).

---

## 1. Repellent System (Pharaoh Ant Strategy)
*Goal: Prevent compute/LLM loops on known-dead branches by tracking negative sentiment.*

### Schema & Database Changes
*   **Migration:** Add fields to the `research_snapshots` table:
    *   `is_repellent` (boolean, default: false)
    *   `repellent_reason` (text, nullable)
    *   `repellent_scope` (string, nullable) — e.g. "domain:loews.com" or "url_prefix:https://example.com/checkout"
*   **Indexes:** Add a database index on `[objective_id, is_repellent]` to ensure rapid queries during task planning and job dispatch.

### Rails Backend Changes
*   **Job Dispatch Circuit Breaker:**
    *   Intercept `TaskExecutorJob` enqueueing logic. 
    *   Before queuing a task, look for any `is_repellent = true` snapshots belonging to the objective that structurally match the pending task's domain or target.
    *   If a match is found, immediately transition the task to `skipped_due_to_repellent` status to prevent unnecessary Solid Queue processing.

### Mac Agent & Tool Changes
*   **Tool Update (`write_research_snapshot`):**
    *   Add optional `sentiment` (enum: `neutral`, `positive`, `negative`), `repellent_reason`, and `repellent_scope` arguments.
    *   Update LLM prompt instructions on strictly *when* to use `negative` sentiment (e.g. "Item is permanently sold out", "Price strictly exceeds max budget") vs temporary failures.

---

## 2. Nutrient Density Scoring
*Goal: Quantify the signal-richness of an objective to determine how many resources it deserves.*

### Schema & Database Changes
*   **Migration:** Add `nutrient_density` (float/integer, default: 0) to the `objectives` table.

### Rails Backend Changes
*   **Scoring Service (`NutrientScorer`):**
    *   Create a callback/service that triggers when native `ObjectiveFeedback` is submitted by the iOS client, or when high-value `ResearchSnapshots` are written.
    *   Algorithm: Scale `nutrient_density` up when actionable, high-delta data arrives. Decay `nutrient_density` passively over time or on repetitive low-signal snapshots.

---

## 3. Dynamic Resource Allocation
*Goal: Dynamically map Solid Queue priority and concurrency limits to an Objective's Nutrient Density.*

### Solid Queue Configuration
*   **Priority Queues:** Update `config/queue_schema.rb` or Solid Queue configuration files to establish multi-tiered queue lanes (e.g., `high_priority`, `default`, `background_scan`).

### Rails Backend Changes
*   **Resource Allocator Service (`ResourceAllocator`):**
    *   Instead of blindly dumping tasks into `TaskExecutorJob`, route tasks based on their parent objective's `nutrient_density`.
    *   Objectives with top 10% density get pushed to the `high_priority` queue.
    *   Provide hard guardrails (e.g., maximum queue depth per objective) so one spike in "nutrient density" doesn't entirely starve out manual iOS composer requests.

---

## 4. Environmental Priming (Exudates)
*Goal: Leave behind navigational breadcrumbs (CSS selectors, bypass tactics) to accelerate future task processing.*

### Schema & Database Changes
*   **Migration:** Add a `snapshot_kind` (enum: `result`, `exudate`) to `research_snapshots` (defaulting to `result`).
*   **Alternative:** Build a dedicated `agent_exudates` table linked to workspaces/domains to persist findings site-wide, not just objective-wide. This requires a `domain_key` field.
*   **TTL Tracking:** Add an `expires_at` column since DOM layouts and anti-bot environments change regularly.

### Mac Agent Changes
*   **Context Injection:** 
    *   During the Objective Planner phase, query the backend for valid `exudate` records tied to the domains in the objective.
    *   Prepend this "prior knowledge" directly into the sandbox instructions (e.g., "Note: use selector `.price-tag-v2` for AcmeCorp.com").
*   **Write Capabilities:**
    *   When the LLM encounters a complex DOM map or timing threshold, allow it to call a `write_exudate` tool to cache struct/knowledge independently of writing research answers.

---

## Phased Rollout Plan

- [ ] **Phase 1: Repellents & Circuit Breaking (High ROI)**
    - Add migrations for Repellent flags on Snapshots.
    - Update `write_research_snapshot` Mac tool.
    - Install `TaskExecutorJob` circuit breaker.
- [ ] **Phase 2: Nutrient Scoring (Foundation for Growth)**
    - Add `nutrient_density` to `objectives`.
    - Build scoring callback triggers in Rails models.
- [ ] **Phase 3: Dynamic Queueing (Throughput Optimization)**
    - Implement tiered Solid Queue routing utilizing Nutrient Scoring.
- [ ] **Phase 4: Exudates (Acceleration)**
    - Roll out dedicated Exudate ingestion in Postgres.
    - Inject matching exudate data into future agent sessions.

