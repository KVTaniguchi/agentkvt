import Foundation

actor AgentMailPoller {
    private let bridge: AgentMailBridge
    private let interval: Int
    private var timer: DispatchSourceTimer?
    private var isPolling = false

    init(bridge: AgentMailBridge, interval: Int) {
        self.bridge = bridge
        self.interval = interval
    }

    func start() async {
        do {
            let inbox = try await bridge.ensureInbox()
            print("[AgentMailPoller] Started - inbox=\(inbox.inboxId) interval=\(interval)s")
        } catch {
            print("[AgentMailPoller] Startup failed: \(error)")
        }

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .seconds(interval))
        timer.setEventHandler { [weak self] in
            Task { await self?.poll() }
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        print("[AgentMailPoller] Stopped")
    }

    private func poll() async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        let writtenCount = await bridge.syncUnreadMessagesToInbox()
        if writtenCount > 0 {
            print("[AgentMailPoller] Wrote \(writtenCount) new AgentMail message(s) to inbox")
        }
    }
}
