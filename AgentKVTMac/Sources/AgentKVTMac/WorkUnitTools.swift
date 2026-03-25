import Foundation
import ManagerCore
import SwiftData

// MARK: - Fetch

public func makeFetchWorkUnitsTool(modelContext: ModelContext) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "fetch_work_units",
        name: "fetch_work_units",
        description: """
            List work units on the shared stigmergy board. Filter by state and/or category. \
            Use with missions whose triggerSchedule is workunit_board to react to multi-step family jobs.
            """,
        parameters: .init(
            type: "object",
            properties: [
                "state": .init(
                    type: "string",
                    description: "Optional: draft, pending, in_progress, blocked, or done. Omit to return all."
                ),
                "category": .init(
                    type: "string",
                    description: "Optional category filter (e.g. travel)."
                ),
            ],
            required: []
        ),
        handler: { args in
            let stateFilter = args["state"] as? String
            let categoryFilter = args["category"] as? String

            let descriptor: FetchDescriptor<WorkUnit>
            if let s = stateFilter, let c = categoryFilter {
                let stateVal = s
                let catVal = c
                descriptor = FetchDescriptor<WorkUnit>(
                    predicate: #Predicate<WorkUnit> { $0.state == stateVal && $0.category == catVal },
                    sortBy: [SortDescriptor(\.priority, order: .reverse), SortDescriptor(\.updatedAt, order: .reverse)]
                )
            } else if let s = stateFilter {
                let stateVal = s
                descriptor = FetchDescriptor<WorkUnit>(
                    predicate: #Predicate<WorkUnit> { $0.state == stateVal },
                    sortBy: [SortDescriptor(\.priority, order: .reverse), SortDescriptor(\.updatedAt, order: .reverse)]
                )
            } else if let c = categoryFilter {
                let catVal = c
                descriptor = FetchDescriptor<WorkUnit>(
                    predicate: #Predicate<WorkUnit> { $0.category == catVal },
                    sortBy: [SortDescriptor(\.priority, order: .reverse), SortDescriptor(\.updatedAt, order: .reverse)]
                )
            } else {
                descriptor = FetchDescriptor<WorkUnit>(
                    sortBy: [SortDescriptor(\.priority, order: .reverse), SortDescriptor(\.updatedAt, order: .reverse)]
                )
            }

            guard let units = try? modelContext.fetch(descriptor), !units.isEmpty else {
                return "No work units match the filter."
            }
            return units.map { u in
                var lines: [String] = [
                    "ID: \(u.id.uuidString)",
                    "Title: \(u.title)",
                    "Category: \(u.category)",
                    "State: \(u.state)",
                    "Priority: \(u.priority)",
                    "Phase hint: \(u.activePhaseHint ?? "")",
                ]
                if let data = u.moundPayload, let json = String(data: data, encoding: .utf8) {
                    lines.append("Mound JSON: \(json)")
                }
                if let pid = u.createdByProfileId {
                    lines.append("Created by profile: \(pid.uuidString)")
                }
                if let claim = u.claimedByMissionId {
                    lines.append("Claimed by mission: \(claim.uuidString)")
                }
                if let until = u.claimedUntil {
                    lines.append("Claim until: \(until.formatted())")
                }
                return lines.joined(separator: "\n")
            }.joined(separator: "\n\n---\n\n")
        }
    )
}

// MARK: - Update

public func makeUpdateWorkUnitTool(modelContext: ModelContext) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "update_work_unit",
        name: "update_work_unit",
        description: "Transition a WorkUnit: set state, optional mound JSON payload, and optional active phase hint.",
        parameters: .init(
            type: "object",
            properties: [
                "work_unit_id": .init(type: "string", description: "UUID of the WorkUnit."),
                "new_state": .init(
                    type: "string",
                    description: "Optional: draft, pending, in_progress, blocked, done."
                ),
                "mound_payload_json": .init(
                    type: "string",
                    description: "Optional UTF-8 JSON string to replace the mound payload."
                ),
                "active_phase_hint": .init(type: "string", description: "Optional short hint for the next step."),
                "priority": .init(type: "double", description: "Optional pheromone priority."),
            ],
            required: ["work_unit_id"]
        ),
        handler: { args in
            guard let idStr = args["work_unit_id"] as? String,
                  let id = UUID(uuidString: idStr) else {
                return "Error: invalid work_unit_id."
            }
            let descriptor = FetchDescriptor<WorkUnit>(
                predicate: #Predicate<WorkUnit> { $0.id == id }
            )
            guard let unit = try? modelContext.fetch(descriptor).first else {
                return "Not found: \(idStr)"
            }
            if let n = args["new_state"] as? String, !n.isEmpty {
                unit.state = n
            }
            if let json = args["mound_payload_json"] as? String {
                unit.moundPayload = json.data(using: .utf8)
            }
            if let hint = args["active_phase_hint"] as? String {
                unit.activePhaseHint = hint
            }
            if let p = args["priority"] as? Double {
                unit.priority = p
            }
            unit.updatedAt = Date()
            try? modelContext.save()
            return "Updated work unit \(idStr)."
        }
    )
}

// MARK: - Ephemeral pins

public func makePinEphemeralNoteTool(modelContext: ModelContext) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "pin_ephemeral_note",
        name: "pin_ephemeral_note",
        description: "Add a short-lived pin that auto-deletes after TTL (evaporates on the next clock tick).",
        parameters: .init(
            type: "object",
            properties: [
                "content": .init(type: "string", description: "Text content."),
                "ttl_seconds": .init(type: "integer", description: "Seconds until evaporation."),
                "strength": .init(type: "double", description: "Optional pheromone strength (default 1.0)."),
                "category": .init(type: "string", description: "Optional category tag."),
            ],
            required: ["content", "ttl_seconds"]
        ),
        handler: { args in
            guard let content = args["content"] as? String else {
                return "Error: content required."
            }
            let ttl: Int
            if let i = args["ttl_seconds"] as? Int {
                ttl = i
            } else if let d = args["ttl_seconds"] as? Double {
                ttl = Int(d)
            } else {
                return "Error: ttl_seconds required."
            }
            guard ttl > 0 else { return "Error: ttl_seconds must be positive." }
            let strength = (args["strength"] as? Double) ?? 1.0
            let category = args["category"] as? String
            let expires = Date().addingTimeInterval(TimeInterval(ttl))
            let pin = EphemeralPin(
                content: content,
                category: category,
                strength: strength,
                expiresAt: expires
            )
            modelContext.insert(pin)
            try? modelContext.save()
            return "Pinned ephemeral note id=\(pin.id.uuidString), expires \(expires.formatted())."
        }
    )
}

// MARK: - Resource health (negative trails)

public func makeListResourceHealthTool(modelContext: ModelContext) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "list_resource_health",
        name: "list_resource_health",
        description: "List resource cooldowns and failure counts so other agents avoid hammering broken endpoints.",
        parameters: .init(type: "object", properties: [:], required: []),
        handler: { _ in
            let descriptor = FetchDescriptor<ResourceHealth>(
                sortBy: [SortDescriptor(\.resourceKey, order: .forward)]
            )
            guard let rows = try? modelContext.fetch(descriptor), !rows.isEmpty else {
                return "No resource health records."
            }
            return rows.map { r in
                var lines = [
                    "Key: \(r.resourceKey)",
                    "Failures: \(r.failureCount)",
                ]
                if let u = r.cooldownUntil {
                    lines.append("Cooldown until: \(u.formatted())")
                }
                if let e = r.lastErrorMessage {
                    lines.append("Last error: \(e)")
                }
                return lines.joined(separator: "\n")
            }.joined(separator: "\n\n---\n\n")
        }
    )
}

public func makeReportResourceFailureTool(modelContext: ModelContext) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "report_resource_failure",
        name: "report_resource_failure",
        description: "Record a failure for a resource key and set a cooldown window so other missions backoff.",
        parameters: .init(
            type: "object",
            properties: [
                "resource_key": .init(type: "string", description: "Stable identifier (e.g. api.example.com/search)."),
                "cooldown_seconds": .init(type: "integer", description: "How long to avoid retrying."),
                "error_message": .init(type: "string", description: "Optional short error message."),
            ],
            required: ["resource_key", "cooldown_seconds"]
        ),
        handler: { args in
            guard let key = args["resource_key"] as? String, !key.isEmpty else {
                return "Error: resource_key required."
            }
            let cd: Int
            if let i = args["cooldown_seconds"] as? Int {
                cd = i
            } else if let d = args["cooldown_seconds"] as? Double {
                cd = Int(d)
            } else {
                return "Error: cooldown_seconds required."
            }
            guard cd > 0 else { return "Error: cooldown_seconds must be positive." }
            let err = args["error_message"] as? String
            let until = Date().addingTimeInterval(TimeInterval(cd))
            let descriptor = FetchDescriptor<ResourceHealth>(
                predicate: #Predicate<ResourceHealth> { $0.resourceKey == key }
            )
            let existing = try? modelContext.fetch(descriptor).first
            let record: ResourceHealth
            if let existing {
                record = existing
            } else {
                record = ResourceHealth(resourceKey: key)
                modelContext.insert(record)
            }
            record.lastFailureAt = Date()
            record.cooldownUntil = until
            record.failureCount += 1
            record.lastErrorMessage = err
            record.updatedAt = Date()
            try? modelContext.save()
            return "Recorded failure for \(key); cooldown until \(until.formatted())."
        }
    )
}

public func makeClearResourceHealthTool(modelContext: ModelContext) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "clear_resource_health",
        name: "clear_resource_health",
        description: "Clear cooldown after a successful call (or delete the record).",
        parameters: .init(
            type: "object",
            properties: [
                "resource_key": .init(type: "string", description: "Stable identifier."),
            ],
            required: ["resource_key"]
        ),
        handler: { args in
            guard let key = args["resource_key"] as? String, !key.isEmpty else {
                return "Error: resource_key required."
            }
            let descriptor = FetchDescriptor<ResourceHealth>(
                predicate: #Predicate<ResourceHealth> { $0.resourceKey == key }
            )
            guard let record = try? modelContext.fetch(descriptor).first else {
                return "No record for \(key)."
            }
            modelContext.delete(record)
            try? modelContext.save()
            return "Cleared resource health for \(key)."
        }
    )
}
