import Foundation
import ManagerCore
import SwiftData

/// MCP tool: returns all unprocessed `IncomingEmailSummary` records synced from iOS.
///
/// The iOS `EdgeSummarizationService` runs Apple Intelligence on-device to produce
/// compact summaries, entity lists, and intent tags. This tool exposes those results
/// to the Mac agent so it can reason over condensed, PII-stripped payloads rather
/// than raw email text.
///
/// Pair with `mark_email_summary_processed` once you have created an `ActionItem`
/// or otherwise acted on the summary.
public func makeFetchEmailSummariesTool(modelContext: ModelContext) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "fetch_email_summaries",
        name: "fetch_email_summaries",
        description: """
            Fetch unprocessed email summaries pre-processed on iPhone using Apple Intelligence. \
            Each record contains: subject, a 1–3 sentence summary, extracted named entities, \
            and an on-device intent classification (e.g. "meeting.request", "invoice.approval"). \
            Use this instead of incoming_email_trigger when processing iOS-side pre-summarized emails. \
            Call mark_email_summary_processed after acting on a summary.
            """,
        parameters: .init(type: "object", properties: [:], required: []),
        handler: { _ in
            let descriptor = FetchDescriptor<IncomingEmailSummary>(
                predicate: #Predicate { !$0.processedByMac },
                sortBy: [SortDescriptor(\.createdAt)]
            )
            guard let summaries = try? modelContext.fetch(descriptor), !summaries.isEmpty else {
                return "No pending email summaries."
            }
            let blocks = summaries.map { s -> String in
                var lines = [
                    "ID: \(s.id.uuidString)",
                    "Subject: \(s.subject)",
                    "Summary: \(s.summary)",
                ]
                if !s.keyEntities.isEmpty {
                    lines.append("Entities: \(s.keyEntities.joined(separator: ", "))")
                }
                if let intent = s.classifiedIntent {
                    lines.append("Intent: \(intent)")
                }
                lines.append("Device: \(s.summarizedOnDevice)")
                lines.append("Received: \(s.createdAt.formatted())")
                return lines.joined(separator: "\n")
            }
            return blocks.joined(separator: "\n\n---\n\n")
        }
    )
}

/// MCP tool: marks an `IncomingEmailSummary` as processed by the Mac agent.
///
/// Call this after you have created an `ActionItem` or otherwise acted on the summary.
/// Prevents the same summary from being returned again by `fetch_email_summaries`.
public func makeMarkEmailSummaryProcessedTool(modelContext: ModelContext) -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "mark_email_summary_processed",
        name: "mark_email_summary_processed",
        description: "Mark an iOS email summary as processed after creating an ActionItem or taking action. Pass the summary's ID from fetch_email_summaries.",
        parameters: .init(
            type: "object",
            properties: [
                "summary_id": .init(
                    type: "string",
                    description: "UUID string of the IncomingEmailSummary to mark as processed."
                ),
                "action_item_id": .init(
                    type: "string",
                    description: "UUID string of the ActionItem created from this summary, if any."
                ),
            ],
            required: ["summary_id"]
        ),
        handler: { args in
            guard let idStr = args["summary_id"] as? String,
                  let id = UUID(uuidString: idStr) else {
                return "Error: missing or invalid summary_id."
            }
            let descriptor = FetchDescriptor<IncomingEmailSummary>(
                predicate: #Predicate { $0.id == id }
            )
            guard let record = try? modelContext.fetch(descriptor).first else {
                return "Not found: \(idStr)"
            }
            record.processedByMac = true
            if let actionIdStr = args["action_item_id"] as? String {
                record.resultingActionItemId = UUID(uuidString: actionIdStr)
            }
            try? modelContext.save()
            return "Marked processed: \(idStr)"
        }
    )
}
