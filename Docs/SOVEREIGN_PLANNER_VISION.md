# AgentKVT: The Sovereign Planner

This document captures the current product vision for AgentKVT so implementation decisions can be checked against a stable reference as the project evolves.

## Vision

AgentKVT is intended to become a localized, private, and proactive life manager that serves as a zero-token-cost alternative to frontier API-driven agents. The product centers deterministic, Apple-native workflows while also offering a dedicated chat interface on Tab 4 for conversational guidance, follow-up, and ad-hoc interaction.

## Product Direction

The long-term direction is to make AgentKVT feel less like a chatbot and more like a sovereign planning system:

- It should run locally on Apple Silicon hardware and scale its reasoning model to available memory.
- It should use Apple-native technologies such as SwiftData, CoreML, and NLP to reduce prompt bloat and keep state grounded in local data structures.
- It should present users with deterministic `ActionItem` choices and structured objective results as the primary control loop, with chat available for conversational interaction.
- It should ingest sensitive personal data locally, sanitize it before model use, and keep the overall system privacy-first.

## Core Pillars

### 1. Hardware-Agnostic Sovereignty

AgentKVT should run across a wide range of Apple Silicon Macs, from lower-memory machines to high-memory workstations. Model selection and reasoning depth should adapt to the device rather than forcing a single heavyweight runtime.

### 2. Apple-Native Intelligence

The system should rely on local Apple-friendly primitives for state, memory, and intent handling. SwiftData remains the backbone for durable memory, while NLP/CoreML-style capabilities reduce the need to stuff raw context into LLM prompts.

### 3. Deterministic Control

The iOS app should function as a structured remote with deterministic controls first, plus chat for follow-up. Users define high-level **Objectives**; the system decomposes them into tasks, researches them, and surfaces results and reviewable `ActionItem`s.

### 4. Privacy-First Ingestion

Personal data sources such as BEE AI transcripts, bank CSVs, and emails should be processed locally. Sanitization should happen before information reaches an LLM-facing step so sensitive data does not leave the trusted environment.

## System Architecture

### The Brain (macOS Service)

A headless background service that performs the heavy lifting.

- `MissionRunner` orchestrates scheduled or triggered mission execution.
- `AgentLoop` interfaces with a local LLM using constrained JSON output for reliability.
- The tool registry provides a sandboxed execution surface for web research, file processing, notifications, and other local actions.

### The Remote (iOS App)

A SwiftUI dashboard that acts as the primary control surface.

- An Objectives tab lets users define goals; the system decomposes them into tasks and researches them.
- An Actions tab surfaces dynamic `ActionItem`s for approval, review, or follow-up.
- A context editor manages the `LifeContext` that grounds planning and personalization.

### The Backend (Rails + Postgres)

The canonical source of truth hosted on the server Mac. iOS and the Mac agent both read and write through the Rails API.

- `Objective`: a user-defined goal that the system decomposes into tasks
- `Task`: a concrete research or synthesis step within an objective
- `ResearchSnapshot`: persisted findings from agent research
- `ActionItem`: the deterministic output surfaced to the user
- `AgentLog`: the audit trail for execution, reasoning outcomes, and debugging
- `LifeContext`: facts the system must remember about the user and household

## Example Mission Patterns

The product vision currently includes objective patterns like:

- **Trip planning**: "Plan San Diego trip logistics" → decomposed into hotel research, flights, activities
- **Job search**: "Find senior iOS roles in SF" → decomposed into job board scanning, resume comparison, outreach tasks
- **Financial tracking**: "Track savings progress for down payment" → decomposed into budget analysis, subscription review
- **Context enrichment**: Ingest BEE AI transcripts and update `LifeContext` when new interests, goals, or priorities emerge

## Hardware Strategy

### Tier 1: 16 GB Macs

Target 7B to 8B models for lightweight planning, low-latency execution, and intent parsing.

### Tier 2: 24 GB to 36 GB Macs

Target 14B to 32B models for stronger reasoning and more capable task decomposition.

### Tier 3: 128 GB Macs

Target 70B+ models for deep document analysis, complex coding assistance, and large reasoning workloads.

## Working Principles

When making roadmap or implementation decisions, we should bias toward:

- local execution over cloud dependence
- deterministic UI (objectives + actions) as the primary workflow, with chat as a complementary interface
- structured memory over prompt-only context
- auditable action generation over opaque autonomy
- privacy-preserving ingestion over convenience shortcuts

## Status Note

This is a vision reference, not a claim that every capability is already implemented. It should be treated as the product north star and updated as the architecture and roadmap become more concrete.
