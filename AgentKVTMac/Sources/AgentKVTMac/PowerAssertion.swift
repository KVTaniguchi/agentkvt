import Foundation
import IOKit.pwr_mgt

// MARK: - PowerAssertion

/// Holds a stack of OS power-management assertions that prevent the Mac Studio / MacBook
/// from suspending the process while the AgentKVT runner is active.
///
/// ## Why two layers?
///
/// **Layer 1 — `ProcessInfo.beginActivity`** targets the *App Nap* scheduler.
/// App Nap is an application-layer policy that throttles background processes by reducing
/// their timer granularity and suspending them between bursts. A headless CLI process
/// is not an "app" in the AppKit sense, but the Activity token still registers the process
/// as doing user-initiated work so `NSBackgroundActivityScheduler` and the process's
/// own cooperative timer coalescing leave it alone.
///
/// **Layer 2 — IOKit `IOPMAssertionCreateWithName`** targets the *kernel power manager*.
/// This is the same mechanism `caffeinate(8)` uses. Two assertions are held:
///
/// | Constant | `caffeinate` flag | Prevents |
/// |---|---|---|
/// | `kIOPMAssertionTypePreventSystemSleep` | `-s` | System sleep — including lid-close sleep |
/// | `kIOPMAssertionTypeNoIdleSleep` | `-i` | Idle sleep — when no user activity for N minutes |
///
/// The IOKit assertions survive App Nap and work whether or not there is a GUI. They are
/// visible in `pmset -g assertions` and `Activity Monitor → Energy`.
///
/// ## Limitations
/// Neither assertion prevents sleep when the Mac is on *battery with the lid closed* and
/// macOS decides the thermal budget is exhausted. For a 24/7 deployment, connect AC power.
/// The launchd plist (see `Deploy/com.agentkvt.runner.plist`) adds `caffeinate -s -i` as
/// an external belt-and-suspenders on top of these programmatic assertions.
public final class PowerAssertion {

    // MARK: - State

    private let activity: NSObjectProtocol
    private var systemSleepID: IOPMAssertionID = 0
    private var idleSleepID:   IOPMAssertionID = 0

    // MARK: - Init / Start

    /// Acquire all power assertions. Logs but does not throw if IOKit fails — the process
    /// will still run; it's just not fully protected from OS sleep.
    public init(reason: String) {
        // ── Layer 1: App Nap prevention ───────────────────────────────────────────
        // .userInitiated          → marks work as foreground-priority (no throttling)
        // .idleSystemSleepDisabled → asks the OS not to sleep the system while idle
        // .suddenTerminationDisabled / .automaticTerminationDisabled → survives
        //   `NSProcessInfo` kill-on-memory-pressure events
        activity = ProcessInfo.processInfo.beginActivity(
            options: [
                .userInitiated,
                .idleSystemSleepDisabled,
                .suddenTerminationDisabled,
                .automaticTerminationDisabled,
            ],
            reason: reason
        )

        // ── Layer 2: IOKit system sleep prevention (≈ caffeinate -s) ─────────────
        // "PreventSystemSleep" is the canonical string that maps to the assertion type
        // used by caffeinate -s. It prevents the system from sleeping even with the
        // lid closed, as long as AC power is connected.
        let kr1 = IOPMAssertionCreateWithName(
            "PreventSystemSleep" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &systemSleepID
        )
        if kr1 != kIOReturnSuccess {
            print("[PowerAssertion] WARNING: PreventSystemSleep assertion failed (kr=\(kr1)). " +
                  "System may sleep during LLM inference.")
        }

        // ── Layer 2b: IOKit idle sleep prevention (≈ caffeinate -i) ─────────────
        // "NoIdleSleepAssertion" prevents sleep triggered by the idle timer (no user
        // input for N minutes). Belt-and-suspenders alongside PreventSystemSleep.
        let kr2 = IOPMAssertionCreateWithName(
            "NoIdleSleepAssertion" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &idleSleepID
        )
        if kr2 != kIOReturnSuccess {
            print("[PowerAssertion] WARNING: NoIdleSleepAssertion failed (kr=\(kr2)).")
        }

        print("[PowerAssertion] Assertions acquired. Verify with: pmset -g assertions")
    }

    // MARK: - Release

    /// Release all assertions back to the OS. Call before process exit.
    public func release() {
        ProcessInfo.processInfo.endActivity(activity)
        if systemSleepID != 0 { IOPMAssertionRelease(systemSleepID) }
        if idleSleepID   != 0 { IOPMAssertionRelease(idleSleepID) }
        print("[PowerAssertion] Assertions released.")
    }
}
