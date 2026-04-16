import Foundation
import ManagerCore
import SwiftData

public func makeReadResearchSnapshotTool(modelContext: ModelContext) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "read_research_snapshot",
        name: "read_research_snapshot",
        description: "Read the last known value for a tracked research metric (e.g. a hotel rate or flight price). Call at mission start to check whether this is the first observation or to compare against a prior value.",
        parameters: .init(
            type: "object",
            properties: [
                "key": .init(type: "string", description: "Logical name of the tracked metric, e.g. 'loews_royal_pacific_rate'")
            ],
            required: ["key"]
        ),
        handler: { args in
            guard let key = args["key"] as? String, !key.isEmpty else {
                return "Error: key is a required non-empty string."
            }
            let descriptor = FetchDescriptor<ResearchSnapshot>(
                predicate: #Predicate<ResearchSnapshot> { $0.key == key }
            )
            guard let snapshot = try? modelContext.fetch(descriptor).first else {
                return "ResearchSnapshot not found for key=\(key). This is the first check."
            }
            let formatter = ISO8601DateFormatter()
            let checkedAtStr = formatter.string(from: snapshot.checkedAt)
            let deltaStr = snapshot.deltaNote ?? "none"
            return "ResearchSnapshot found: key=\(snapshot.key) lastKnownValue=\(snapshot.lastKnownValue) checkedAt=\(checkedAtStr) deltaNote=\(deltaStr)"
        }
    )
}

public func makeWriteResearchSnapshotTool(modelContext: ModelContext) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "write_research_snapshot",
        name: "write_research_snapshot",
        description: "Persist the current observed value for a tracked research metric and detect meaningful change. Returns 'changed: ...' when a notable delta is found, 'unchanged: ...' otherwise.",
        parameters: .init(
            type: "object",
            properties: [
                "key": .init(type: "string", description: "Logical name of the tracked metric, e.g. 'loews_royal_pacific_rate'"),
                "currentValue": .init(type: "string", description: "The newly observed value (price, count, text, etc.)"),
                "deltaThreshold": .init(type: "string", description: "Optional. Numeric threshold for meaningful change (default '0', meaning any change counts). E.g. '10' suppresses notifications for price moves under $10.")
            ],
            required: ["key", "currentValue"]
        ),
        handler: { args in
            guard let key = args["key"] as? String, !key.isEmpty,
                  let currentValue = args["currentValue"] as? String else {
                return "Error: key and currentValue are required."
            }
            let thresholdStr = args["deltaThreshold"] as? String ?? "0"
            let threshold = Double(thresholdStr) ?? 0.0

            let descriptor = FetchDescriptor<ResearchSnapshot>(
                predicate: #Predicate<ResearchSnapshot> { $0.key == key }
            )
            let existing = try? modelContext.fetch(descriptor).first

            guard let snapshot = existing else {
                let record = ResearchSnapshot(key: key, lastKnownValue: currentValue)
                modelContext.insert(record)
                try? modelContext.save()
                return "ResearchSnapshot created: first observation of key=\(key) value=\(currentValue)"
            }

            let previous = snapshot.lastKnownValue

            if previous == currentValue {
                snapshot.checkedAt = Date()
                snapshot.deltaNote = nil
                try? modelContext.save()
                return "unchanged: value=\(currentValue)"
            }

            // Attempt numeric delta evaluation
            if let prevDouble = Double(previous), let currDouble = Double(currentValue) {
                let delta = abs(currDouble - prevDouble)
                if threshold > 0 && delta <= threshold {
                    snapshot.checkedAt = Date()
                    snapshot.deltaNote = nil
                    snapshot.lastKnownValue = currentValue
                    try? modelContext.save()
                    return "unchanged: value=\(currentValue) (numeric delta \(delta) below threshold=\(threshold))"
                }
            }

            let note = "Changed from \(previous) to \(currentValue)"
            snapshot.lastKnownValue = currentValue
            snapshot.checkedAt = Date()
            snapshot.deltaNote = note
            try? modelContext.save()
            return "changed: \(note)"
        }
    )
}
