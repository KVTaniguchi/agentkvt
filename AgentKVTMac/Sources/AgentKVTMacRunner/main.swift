import AgentKVTMac
import Foundation

// Top-level async entry point (SPM executable target, no @main required).
//
// Lifecycle:
//   1. Acquire power assertions — prevents App Nap and system sleep.
//   2. Start the runner and signal handler as concurrent child tasks.
//   3. Wait for whichever finishes first:
//        • Signal task: SIGINT/SIGTERM received → graceful shutdown path.
//        • Runner task: only exits on fatal error (unexpected).
//   4. Cancel remaining tasks, release power assertions, exit cleanly.
//
// The structured TaskGroup means Swift Concurrency owns the lifetime of both
// tasks. When we call group.cancelAll(), cooperative cancellation propagates
// into the MissionExecutionQueue's `for await` drain loop, which terminates at
// the next suspension point.

let logFile = await RuntimeLogCapture.configure(
    processLabel: "AgentKVTMacRunner",
    logFileURL: RuntimeLogCapture.defaultFileURL
)
print("[Logging] Writing logs to \(logFile.path)")

let assertion = PowerAssertion(
    reason: "AgentKVT: background agent must remain active for CloudKit sync and LLM inference"
)

let signals = SignalHandler()

await withTaskGroup(of: Void.self) { group in

    // Task A: the actual runner — runs forever under normal operation.
    group.addTask {
        await runAgentKVTMacRunner()
        // Reaching here means the runner returned (should not happen in scheduler mode).
        print("[Main] Runner exited unexpectedly.")
    }

    // Task B: wait for SIGINT or SIGTERM.
    group.addTask {
        await signals.waitForShutdown()
    }

    // Block until the first task completes (either a signal or an unexpected runner exit).
    await group.next()

    // Cancel whichever task is still running.
    group.cancelAll()
}

// Release IOKit assertions and ProcessInfo activity so the OS reclaims them
// immediately rather than waiting for the kernel's assertion timeout.
assertion.release()

print("[Main] AgentKVT runner stopped.")
exit(0)
