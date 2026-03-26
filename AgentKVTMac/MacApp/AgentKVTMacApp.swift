import SwiftUI
import AgentKVTMac

@main
struct AgentKVTMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            let logFile = await RuntimeLogCapture.configure(processLabel: "AgentKVTMacApp")
            print("[Logging] Writing logs to \(logFile.path)")
            await runAgentKVTMacRunner()
        }
    }
}
