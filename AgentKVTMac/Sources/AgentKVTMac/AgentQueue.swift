import Foundation

/// Serial, priority-aware work queue for the agent runner.
///
/// All triggers (FSEvents, email, webhook, clock tick) funnel through here so the LLM
/// is never invoked in parallel — trading real-time latency for maximum per-task quality
/// and deterministic resource usage on the M4 Max.
///
/// Design: a priority-sorted in-memory buffer feeds a signal-only `AsyncStream<Void>`.
/// The consumer drains the full buffer (highest-priority first) after each signal, so a
/// burst of low-priority clock ticks never delays a high-priority webhook.
///
/// Back-pressure: when the buffer reaches `maxBufferSize` (64), the lowest-priority
/// buffered item is evicted to make room. If the incoming item has lower priority than
/// all buffered items it is dropped and `droppedCount` increments.
actor AgentQueue {

    // MARK: - Public Types

    enum Priority: Int, Comparable, Sendable {
        case low    = 0
        case normal = 1
        case high   = 2

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum WorkItem: Sendable {
        /// 60-second clock tick: check for due scheduled missions and pending chat messages.
        case clockTick
        /// A new .eml file landed in the inbox directory.
        case emailFile(URL)
        /// A new file landed in the inbound (dropzone) directory.
        case inboundFile(URL)
        /// A POST payload arrived on the local webhook listener.
        case webhook(String)
        /// LAN-only: JSON body `{"agentkvt":"process_chat"}` on the webhook port — drain pending chat only.
        case processPendingChat
        /// CloudKit remote change: iOS synced SwiftData (chat, email summaries, etc.).
        case cloudKitSync
    }

    // MARK: - Configuration

    static let maxBufferSize = 64

    // MARK: - State

    /// Signal stream — yields `Void` whenever new work is available.
    /// Consumer should call `dequeueNext()` in a loop after each signal.
    let workAvailable: AsyncStream<Void>

    /// Total items dropped due to buffer pressure.
    private(set) var droppedCount = 0
    /// Total items successfully dequeued and handed to the consumer.
    private(set) var processedCount = 0

    // MARK: - Internals

    private struct PrioritizedItem: Sendable {
        let priority: Priority
        let workItem: WorkItem
        let enqueuedAt: Date
    }

    private var buffer: [PrioritizedItem] = []
    private var signalContinuation: AsyncStream<Void>.Continuation?

    // MARK: - Init

    init() {
        var cont: AsyncStream<Void>.Continuation!
        // bufferingNewest(1): a single unconsumed signal is enough to wake the drain loop.
        // We never need more than one outstanding wake-up because the drain loop empties
        // the entire priority buffer before waiting for the next signal.
        workAvailable = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        signalContinuation = cont
    }

    // MARK: - Producer API

    /// Append a work item to the priority buffer. Thread-safe via actor isolation.
    /// - Parameters:
    ///   - item: The work to enqueue.
    ///   - priority: Scheduling priority. Defaults to `.normal`.
    func enqueue(_ item: WorkItem, priority: Priority = .normal) {
        if buffer.count >= Self.maxBufferSize {
            // Find the lowest-priority item currently buffered.
            if let evictIdx = buffer.indices.min(by: { buffer[$0].priority < buffer[$1].priority }),
               buffer[evictIdx].priority < priority {
                // Evict it to make room for the higher-priority incoming item.
                buffer.remove(at: evictIdx)
                droppedCount += 1
            } else {
                // Buffer is full with equal-or-higher priority items — drop the incoming one.
                droppedCount += 1
                return
            }
        }

        buffer.append(PrioritizedItem(priority: priority, workItem: item, enqueuedAt: Date()))
        // Maintain descending priority order so `removeFirst()` always yields the best item.
        buffer.sort { $0.priority > $1.priority }
        signalContinuation?.yield(())
    }

    // MARK: - Consumer API

    /// Returns the next highest-priority work item, or `nil` if the buffer is empty.
    /// Call this in a `while let` loop after receiving a signal from `workAvailable`.
    func dequeueNext() -> WorkItem? {
        guard !buffer.isEmpty else { return nil }
        let item = buffer.removeFirst()
        processedCount += 1
        return item.workItem
    }

    /// Number of items currently waiting in the buffer.
    var bufferCount: Int { buffer.count }

    /// Finishes the wake stream so long-running drain loops can exit during shutdown.
    func finish() {
        signalContinuation?.finish()
        signalContinuation = nil
    }
}
