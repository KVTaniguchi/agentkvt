import Foundation

// MARK: - SignalHandler

/// Bridges POSIX signals into Swift Structured Concurrency.
///
/// Usage:
/// ```swift
/// let signals = SignalHandler()
/// await signals.waitForShutdown()   // suspends until SIGINT or SIGTERM
/// ```
///
/// ## Why `DispatchSourceSignal` instead of `signal(2)`?
///
/// The raw `signal(2)` handler runs on whichever thread interrupted the process,
/// with almost no safe operations available. `DispatchSourceSignal` delivers the
/// signal as an event to a known `DispatchQueue`, where full Swift runtime is
/// available. This lets us safely call async continuations and actor methods.
///
/// ## The SIG_IGN dance
/// `DispatchSource.makeSignalSource` requires the signal to be *ignored at the
/// process level first* (`signal(SIGINT, SIG_IGN)`). The dispatch source then
/// intercepts it before the kernel default action (termination) takes place.
/// The original `SIG_DFL` is restored on teardown so the second Ctrl-C works
/// normally if shutdown is taking too long.
public final class SignalHandler: @unchecked Sendable {
    public init() {}

    // MARK: - State

    private var sources: [DispatchSourceSignal] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private let lock = NSLock()

    // MARK: - Public API

    /// Suspends until SIGINT (Ctrl-C) or SIGTERM (`kill`, `launchctl stop`) arrives.
    /// Safe to call from any actor or Task context.
    public func waitForShutdown() async {
        await withCheckedContinuation { [weak self] continuation in
            guard let self else { continuation.resume(); return }
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()
            self.installHandler(for: SIGINT,  name: "SIGINT")
            self.installHandler(for: SIGTERM, name: "SIGTERM")
        }
    }

    // MARK: - Internals

    private func installHandler(for sig: Int32, name: String) {
        // Step 1: Tell the kernel to ignore the signal at the default-action level.
        // Without this, the dispatch source competes with the default SIGINT handler
        // and the process terminates before our event handler fires.
        Foundation.signal(sig, SIG_IGN)

        let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
        source.setEventHandler { [weak self] in
            self?.handle(signal: sig, name: name)
        }
        source.setCancelHandler {
            // Restore default behaviour so a second signal terminates the process
            // if graceful shutdown stalls.
            Foundation.signal(sig, SIG_DFL)
        }
        source.resume()

        lock.lock()
        sources.append(source)
        lock.unlock()
    }

    private func handle(signal: Int32, name: String) {
        print("\n[SignalHandler] \(name) received — beginning graceful shutdown.")

        lock.lock()
        let cont = continuation
        continuation = nil
        let toCancel = sources
        sources = []
        lock.unlock()

        // Cancel all sources before resuming the continuation so no second signal
        // fires the handler again.
        toCancel.forEach { $0.cancel() }
        cont?.resume()
    }
}
