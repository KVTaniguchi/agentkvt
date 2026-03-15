# ManagerCore Schema

Shared SwiftData schema for the AgentKVT system (Brain on macOS, Remote on iOS). All entities are in the `ManagerCore` package and used by both apps.

## Entities

### LifeContext
Static facts and user preferences the agent consults before taking action.

| Property   | Type   | Description                          |
|-----------|--------|--------------------------------------|
| id        | UUID   | Unique identifier                    |
| key       | String | Fact key (e.g. "goals", "location")  |
| value     | String | Fact value                           |
| updatedAt | Date   | Last update time                     |

### MissionDefinition
User-defined mission configuration. The Mac agent runs these on a schedule.

| Property          | Type     | Description                                                |
|-------------------|----------|------------------------------------------------------------|
| id                | UUID     | Unique identifier                                          |
| missionName       | String   | Display name (e.g. "Tech Job Scout", "Budget Sentinel")    |
| systemPrompt      | String   | User-defined LLM instructions                             |
| triggerSchedule   | String   | Encoded schedule: `daily|HH:mm`, `weekly|weekday`, `webhook` |
| allowedMCPTools   | [String] | Tool IDs this mission may use (least privilege)             |
| isEnabled         | Bool     | Whether the mission is active                              |
| createdAt         | Date     | Creation time                                              |
| updatedAt         | Date     | Last update time                                           |

### ActionItem
Dynamic button data for the iOS dashboard. Written by the Mac agent; iOS renders as AppIntentButtons.

| Property       | Type   | Description                              |
|----------------|--------|------------------------------------------|
| id             | UUID   | Unique identifier                        |
| title          | String | Button label (e.g. "Review New Job Leads")|
| systemIntent   | String | Intent identifier for the button         |
| payloadData    | Data?  | Optional payload                          |
| relevanceScore | Double | Sort/priority (default 1.0)               |
| timestamp      | Date   | When the item was created                 |
| missionId      | UUID?  | Source mission (optional)                 |
| isHandled      | Bool   | Whether the user has acted on it          |

### AgentLog
Append-only audit log of agent reasoning, tool calls, and outcomes.

| Property    | Type   | Description                    |
|-------------|--------|--------------------------------|
| id          | UUID   | Unique identifier              |
| missionId   | UUID?  | Related mission                |
| missionName | String?| Mission name at time of log    |
| phase       | String | e.g. "reasoning", "tool_call", "outcome" |
| content     | String | Log message or result          |
| toolName    | String?| Tool invoked (if phase is tool_call) |
| timestamp   | Date   | When the entry was written     |

## ModelContainer setup

Apps must create a `ModelContainer` with the full schema:

```swift
import SwiftData
import ManagerCore

let schema = Schema([
    LifeContext.self,
    MissionDefinition.self,
    ActionItem.self,
    AgentLog.self
])
let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
let container = try ModelContainer(for: schema, configurations: [config])
```

## Sync

Sync strategy is documented in `Docs/SYNC.md` in the repository root. Both Mac and iOS use the same schema so that shared state (CloudKit or local network) can replicate correctly.
