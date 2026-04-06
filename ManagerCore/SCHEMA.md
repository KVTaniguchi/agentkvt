# ManagerCore Schema

Shared SwiftData schema for the AgentKVT system (Brain on macOS, Remote on iOS). All entities are in the `ManagerCore` package and used by both apps.

## Core Entities

### LifeContext
Static facts and user preferences the agent consults before taking action.

| Property   | Type   | Description                          |
|-----------|--------|--------------------------------------|
| id        | UUID   | Unique identifier                    |
| key       | String | Fact key (e.g. "goals", "location")  |
| value     | String | Fact value                           |
| updatedAt | Date   | Last update time                     |

### ActionItem
Dynamic button data for the iOS dashboard. Written by the Mac agent; iOS renders as intent-routed buttons.

| Property       | Type   | Description                              |
|----------------|--------|------------------------------------------|
| id             | UUID   | Unique identifier                        |
| title          | String | Button label (e.g. "Review New Job Leads")|
| systemIntent   | String | Intent identifier for the button         |
| payloadData    | Data?  | Optional payload                          |
| relevanceScore | Double | Sort/priority (default 1.0)               |
| timestamp      | Date   | When the item was created                 |
| missionId      | UUID?  | Source mission (optional, legacy)         |
| isHandled      | Bool   | Whether the user has acted on it          |

### AgentLog
Append-only audit log of agent reasoning, tool calls, and outcomes.

| Property    | Type   | Description                    |
|-------------|--------|--------------------------------|
| id          | UUID   | Unique identifier              |
| missionId   | UUID?  | Related mission (legacy)       |
| missionName | String?| Mission/task name at log time  |
| phase       | String | e.g. "start", "tool_call", "tool_result", "assistant", "assistant_final", "outcome", "error", "warning" |
| content     | String | Log message or result          |
| toolName    | String?| Tool invoked (if phase is tool_call) |
| timestamp   | Date   | When the entry was written     |

### FamilyMember
In-app identity for family attribution.

| Property      | Type    | Description                  |
|---------------|---------|------------------------------|
| id            | UUID    | Unique identifier            |
| displayName   | String  | Display name                 |
| symbol        | String? | Emoji or symbol              |
| isAdmin       | Bool    | Admin privileges             |
| createdAt     | Date    | Creation time                |

---

## Chat Entities

### ChatThread
Conversation thread between a family member and the agent.

| Property     | Type     | Description                          |
|-------------|----------|--------------------------------------|
| id          | UUID     | Unique identifier                    |
| title       | String   | Thread title                         |
| status      | String   | "pending", "active", "completed"     |
| createdBy   | UUID?    | Family member who started the thread |
| createdAt   | Date     | Creation time                        |
| updatedAt   | Date     | Last update time                     |

### ChatMessage
Individual message within a chat thread.

| Property     | Type     | Description                          |
|-------------|----------|--------------------------------------|
| id          | UUID     | Unique identifier                    |
| threadId    | UUID     | Parent chat thread                   |
| role        | String   | "user" or "assistant"                |
| content     | String   | Message text                         |
| status      | String   | "pending", "delivered", "failed"     |
| createdAt   | Date     | Creation time                        |

---

## Research & Work Entities

### WorkUnit
Stigmergy board task with state tracking.

| Property     | Type     | Description                          |
|-------------|----------|--------------------------------------|
| id          | UUID     | Unique identifier                    |
| category    | String   | Task category                        |
| state       | String   | Current state                        |
| phase       | String?  | Optional sub-phase                   |
| payload     | String?  | JSON payload                         |
| createdAt   | Date     | Creation time                        |
| updatedAt   | Date     | Last update time                     |

### EphemeralPin
Short-lived note with TTL.

| Property     | Type     | Description                          |
|-------------|----------|--------------------------------------|
| id          | UUID     | Unique identifier                    |
| content     | String   | Note content                         |
| expiresAt   | Date     | Expiration time                      |
| createdAt   | Date     | Creation time                        |

### ResourceHealth
Cooldown/backoff tracking for external resources.

| Property     | Type     | Description                          |
|-------------|----------|--------------------------------------|
| id          | UUID     | Unique identifier                    |
| resourceKey | String   | Resource identifier                  |
| failCount   | Int      | Number of failures                   |
| cooldownUntil| Date?   | End of cooldown period               |
| lastError   | String?  | Last error message                   |
| updatedAt   | Date     | Last update time                     |

### ResearchSnapshot
Persisted research findings for delta tracking.

| Property     | Type     | Description                          |
|-------------|----------|--------------------------------------|
| id          | UUID     | Unique identifier                    |
| key         | String   | Research key                         |
| value       | String   | Observed value                       |
| timestamp   | Date     | When the snapshot was taken           |

### InboundFile
Uploaded file tracking.

| Property           | Type     | Description                          |
|-------------------|----------|--------------------------------------|
| id                | UUID     | Unique identifier                    |
| fileName          | String   | Original file name                   |
| contentType       | String?  | MIME type                            |
| isProcessed       | Bool     | Whether the agent has processed it   |
| uploadedByProfileId| UUID?   | Family member who uploaded           |
| timestamp         | Date     | Upload time                          |

---

## Ingestion Entities

### IncomingEmailSummary
Pre-summarized emails from the CloudKit bridge (iOS edge processing).

| Property     | Type     | Description                          |
|-------------|----------|--------------------------------------|
| id          | UUID     | Unique identifier                    |
| subject     | String   | Email subject                        |
| senderHint  | String?  | Sender identifier                    |
| summary     | String   | Summarized content                   |
| isProcessed | Bool     | Whether the agent has processed it   |
| receivedAt  | Date     | When the email arrived               |
| processedAt | Date?    | When the agent processed it          |

---

## Legacy Entities

### ~~MissionDefinition~~ *(Deprecated)*

> **Note:** MissionDefinition is superseded by server-side Objectives. It remains in ManagerCore for test compatibility but is not used in production by the iOS app. The iOS app uses `IOSBackendObjective` from the Rails API instead.

| Property          | Type     | Description                                                |
|-------------------|----------|------------------------------------------------------------|
| id                | UUID     | Unique identifier                                          |
| missionName       | String   | Display name                                               |
| systemPrompt      | String   | User-defined LLM instructions                             |
| triggerSchedule   | String   | Encoded schedule                                           |
| allowedMCPTools   | [String] | Tool IDs                                                   |
| isEnabled         | Bool     | Whether active                                             |
| createdAt         | Date     | Creation time                                              |
| updatedAt         | Date     | Last update time                                           |

---

## ModelContainer Setup

Apps must create a `ModelContainer` with the full schema:

```swift
import SwiftData
import ManagerCore

let schema = Schema([
    LifeContext.self,
    ActionItem.self,
    AgentLog.self,
    FamilyMember.self,
    ChatThread.self,
    ChatMessage.self,
    WorkUnit.self,
    EphemeralPin.self,
    ResourceHealth.self,
    ResearchSnapshot.self,
    InboundFile.self,
    IncomingEmailSummary.self,
])
let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
let container = try ModelContainer(for: schema, configurations: [config])
```

## Sync

The canonical sync strategy uses a Rails API backend. Both Mac and iOS communicate with the server via HTTP. See `Docs/SYNC.md` in the repository root.
