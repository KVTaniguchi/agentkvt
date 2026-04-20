# Stigmergic Execution Engine: Strategy & Implementation

This document outlines the transition of AgentKVT from a "Simple Scraper" to a "Synthesis Engine" powered by Stigmergic Research principles and Bio-Signal Intelligence.

## 1. The "Schema-First" Task Protocol
Instead of the `ObjectivePlanner` writing prose descriptions, we enforce a strict JSON-schema output. This forces the LLM to think in terms of available Rails services and Mac Runner tools.

- **ObjectivePlanner Overhaul**: Replace "You are a helpful assistant" with "You are a Task Orchestrator."
- **Constraint**: Output ONLY valid JSON tool calls.
- **Human in the Loop**: If the objective cannot be solved with existing tools, the planner must output a `RequestHumanClarification` call.

## 2. The Execution Loop: Check-Act-Verify
We implement a "Check-Act-Verify" cycle within the `TaskExecutorJob` to ensure efficiency and accuracy.

1.  **Check**: Does the `nutrient_density` of the current objective allow for further spend?
2.  **Act**: Execute the Tool Call.
3.  **Verify**: Use a second, smaller model (e.g., 4-bit local Llama) to verify the tool's output matches the expected schema.

## 3. The Scout/Specialist Functional Split
Discovery is separated from synthesis to prevent "hallucination loops."

### ScoutService (Discovery)
- **Role**: Pure discovery. Only metrics are "Coverage" and "Nutrient Potential."
- **Action**: Populates the `research_snapshots` table. Forbidden from updating Objective status.

### SpecialistService (Synthesis)
- **Role**: Pure synthesis.
- **Trigger**: Wakes up only when `NutrientScorer` flags a high-density cluster of snapshots.
- **Action**: Produces the final "Synthesis" output (e.g., the final Universal Studios itinerary).

## 4. Bio-Signal Infrastructure
Guarding the agent against dead ends and prioritizing high-signal info.

- **NutrientScorer Logic**:
    - **+10 Nutrient**: Whitelisted Domain (Orlando Informer, Magic Guides).
    - **-50 Nutrient (Repellent)**: User flags as "Sub-par" or "Irrelevant."
    - **Decay**: Score reduces by 5% every 24 hours to ensure freshness.

## 5. Implementation Roadmap

### Phase 1: Foundation
- [ ] **Run Migrations**: Activate dormant Bio-Signal fields.
- [ ] **Update Mac Tooling**: Add `nutrient_signal` to `WriteObjectiveSnapshotTool.swift`.

### Phase 2: Orchestration
- [ ] **Rewrite ObjectivePlanner**: Enforce JSON output.
- [ ] **Update TaskExecutorJob**: Implement Check-Act-Verify loop.

### Phase 3: Services
- [ ] **New ScoutService**: Build pure discovery logic.
- [ ] **New SpecialistService**: Build synthesis logic.
- [ ] **New NutrientScorer**: Implement scoring and decay background jobs.

---

*This document serves as the architectural source of truth for the AgentKVT Execution Engine transition.*
