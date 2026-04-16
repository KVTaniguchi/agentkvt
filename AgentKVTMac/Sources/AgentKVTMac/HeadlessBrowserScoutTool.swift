import Foundation
import WebKit
import AppKit

/// Headless browser tool for JS-heavy sites (LinkedIn, banks, etc.). Uses WKWebView on macOS
/// to load a URL, optionally run actions (click, fill), and return page content as clean text.
/// Runs entirely headlessly (off-screen window) on the Mac Studio.
public func makeHeadlessBrowserScoutTool() -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "headless_browser_scout",
        name: "headless_browser_scout",
        description: """
            Load a URL in a headless browser (WebKit), optionally perform actions (click selector, fill field),
            then return the page content as text. Use for sites that require JavaScript (e.g. LinkedIn, banking).
            The agent can "act" like a human—clicking buttons and filling fields—without a visible window.
            """,
        parameters: .init(
            type: "object",
            properties: [
                "url": .init(type: "string", description: "Full HTTPS URL to load (must match the mission—e.g. a page the user asked you to open or scrape)."),
                "actions_json": .init(type: "string", description: "Optional. JSON array of actions: [{\"type\":\"click\",\"selector\":\"button.primary\"}, {\"type\":\"fill\",\"selector\":\"#email\",\"value\":\"user@example.com\"}]"),
                "extract_selector": .init(type: "string", description: "Optional CSS selector to extract text from a specific element instead of the entire page.")
            ],
            required: ["url"]
        ),
        handler: { args in
            guard let urlString = args["url"] as? String, !urlString.trimmingCharacters(in: .whitespaces).isEmpty else {
                return "Error: url is required and must be non-empty."
            }
            let actionsJson = args["actions_json"] as? String
            let extractSelector = args["extract_selector"] as? String
            return await HeadlessBrowserScout.run(url: urlString.trimmingCharacters(in: .whitespaces), actionsJson: actionsJson, extractSelector: extractSelector)
        }
    )
}

enum HeadlessBrowserScout {
    /// Load URL (and optional actions), return extracted page content.
    static func run(url: String, actionsJson: String?, extractSelector: String?) async -> String {
        guard let parsed = URL(string: url), parsed.scheme == "https" || parsed.scheme == "http" else {
            return "Error: invalid or unsupported URL (must be http/https)."
        }

        let actions: [BrowserAction] = (actionsJson?.data(using: .utf8)).flatMap { data in
            (try? JSONDecoder().decode([BrowserAction].self, from: data)) ?? []
        } ?? []

        return await runOnMain(url: parsed, actions: actions, extractSelector: extractSelector)
    }

    @MainActor
    private static func runOnMain(url: URL, actions: [BrowserAction], extractSelector: String?) async -> String {
        await withCheckedContinuation { continuation in
            var resumed = false
            let resumeOnce: (String) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: result)
            }

            let config = WKWebViewConfiguration()
            let prefs = WKWebpagePreferences()
            prefs.preferredContentMode = .desktop
            config.defaultWebpagePreferences = prefs

            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
            webView.setValue(false, forKey: "drawsBackground")

            let window = NSWindow(
                contentRect: CGRect(x: -10000, y: -10000, width: 1024, height: 768),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.contentView = NSView()
            window.contentView?.addSubview(webView)
            webView.frame = window.contentView?.bounds ?? .zero

            let delegate = NavigationDelegate(
                actions: actions,
                extractSelector: extractSelector,
                window: window,
                onDone: { result in
                    window.close()
                    resumeOnce(result)
                }
            )
            webView.navigationDelegate = delegate
            webView.load(URLRequest(url: url))

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if !delegate.didFinish {
                    window.close()
                    resumeOnce("Error: headless browser timed out after 30s loading \(url.absoluteString)")
                }
            }
        }
    }
}

private struct BrowserAction: Codable {
    let type: String  // "click" | "fill"
    let selector: String?
    let value: String?
}

private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    let actions: [BrowserAction]
    let extractSelector: String?
    weak var window: NSWindow?
    let onDone: (String) -> Void
    private let lock = NSLock()
    var didFinish = false

    init(actions: [BrowserAction], extractSelector: String?, window: NSWindow, onDone: @escaping (String) -> Void) {
        self.actions = actions
        self.extractSelector = extractSelector
        self.window = window
        self.onDone = onDone
    }

    private func finish(_ result: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !didFinish else { return }
        didFinish = true
        onDone(result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        runActionsAndExtract(webView: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish("Error: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish("Error: \(error.localizedDescription)")
    }

    private func runActionsAndExtract(webView: WKWebView) {
        let js = buildActionScript(actions: actions)
        webView.evaluateJavaScript(js) { [weak self] _, _ in
            guard let self = self else { return }
            // Allow time for click/fill to take effect (e.g. navigation or DOM update)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.extractContent(webView: webView)
            }
        }
    }

    private func buildActionScript(actions: [BrowserAction]) -> String {
        var steps: [String] = []
        for action in actions {
            guard let selector = action.selector, !selector.isEmpty else { continue }
            let safeSelector = selector.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            switch action.type.lowercased() {
            case "click":
                steps.append("(function(){ var e = document.querySelector(\"\(safeSelector)\"); if(e) e.click(); })();")
            case "fill":
                let val = (action.value ?? "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
                steps.append("(function(){ var e = document.querySelector(\"\(safeSelector)\"); if(e) { e.value = \"\(val)\"; e.dispatchEvent(new Event('input', { bubbles: true })); } })();")
            default:
                break
            }
        }
        return steps.isEmpty ? "" : steps.joined(separator: " ")
    }

    private func extractContent(webView: WKWebView) {
        let safeSelector = extractSelector?.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") ?? ""
        let rootNode = safeSelector.isEmpty ? "document.body" : "document.querySelector(\"\(safeSelector)\") || document.body"
        
        let script = """
        (function() {
            var body = \(rootNode);
            if (!body) return '';
            var clone = body.cloneNode(true);
            var scripts = clone.querySelectorAll('script, style, nav, footer, [role="banner"]');
            scripts.forEach(function(s) { s.remove(); });
            var text = clone.innerText || clone.textContent || '';
            return text.replace(/\\s+/g, ' ').trim().slice(0, 25000);
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] raw, error in
            guard let self = self else { return }
            if let err = error {
                self.finish("Error: \(err.localizedDescription)")
                return
            }
            let content = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cleaned = content.isEmpty ? "(No text content)" : String(content.prefix(14000))
            if content.count > 14000 {
                self.finish(cleaned + "\n\n[Content truncated for context.]")
            } else {
                self.finish(cleaned)
            }
        }
    }
}
