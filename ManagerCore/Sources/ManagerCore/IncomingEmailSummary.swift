import Foundation
import SwiftData

/// A lightweight email summary written by the iOS edge pre-processor using Apple Intelligence.
/// Synced via CloudKit to the Mac, where the agent reasons over the compact payload
/// rather than piping the full raw email text across the wire.
@Model
public final class IncomingEmailSummary {
    public var id: UUID = UUID()
    /// Original email subject line (not body — keeps this record compact).
    public var subject: String = ""
    /// 1–3 sentence summary produced by Apple Intelligence on the iOS device.
    public var summary: String = ""
    /// Key named entities extracted by NLTagger (people, orgs, places). Max 10.
    public var keyEntities: [String] = []
    /// Lightweight on-device intent classification (e.g. "meeting.request", "invoice.approval").
    public var classifiedIntent: String?
    /// Device name that ran the summarization — for audit and hardware-tier tracking.
    public var summarizedOnDevice: String = ""
    /// When the iOS device created this summary.
    public var createdAt: Date = Date()
    /// Set to true by the Mac agent once it has processed this summary into an ActionItem.
    public var processedByMac: Bool = false
    /// UUID of the ActionItem the Mac agent created from this summary, if any.
    public var resultingActionItemId: UUID?

    public init(
        id: UUID = UUID(),
        subject: String,
        summary: String,
        keyEntities: [String] = [],
        classifiedIntent: String? = nil,
        summarizedOnDevice: String = "",
        createdAt: Date = Date(),
        processedByMac: Bool = false,
        resultingActionItemId: UUID? = nil
    ) {
        self.id = id
        self.subject = subject
        self.summary = summary
        self.keyEntities = keyEntities
        self.classifiedIntent = classifiedIntent
        self.summarizedOnDevice = summarizedOnDevice
        self.createdAt = createdAt
        self.processedByMac = processedByMac
        self.resultingActionItemId = resultingActionItemId
    }
}
