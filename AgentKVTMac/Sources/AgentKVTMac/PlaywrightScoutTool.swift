import Foundation

/// A tool that uses the Node.js Playwright helper (site-scout.js) to perform robust browser automation.
/// This is the "Active Hand" for tasks like interacting with e-commerce sites.
public func makePlaywrightScoutTool() -> ToolRegistry.Tool {
    ToolRegistry.Tool(
        id: "site_scout",
        name: "site_scout",
        description: """
            Perform advanced browser automation using Playwright. Use this for sites that require complex 
            interactions (clicking, filling forms, waiting for elements) or have bot protection (e.g., Target, Amazon).
            Allows for session persistence (login state).
            """,
        parameters: .init(
            type: "object",
            properties: [
                "url": .init(type: "string", description: "The URL to navigate to."),
                "actions": .init(
                    type: "array",
                    description: "Optional. List of actions: [{\"type\":\"click\",\"selector\":\"#btn\"}, {\"type\":\"fill\",\"selector\":\"#search\",\"value\":\"shoes\"}, {\"type\":\"wait\",\"waitMs\":2000}]"
                ),
                "use_session": .init(type: "boolean", description: "Optional. If true, use saved session state (cookies/login).")
            ],
            required: ["url"]
        ),
        handler: { args in
            guard let url = args["url"] as? String else {
                return "Error: url is required."
            }
            
            let actions = args["actions"] as? [[String: Any]] ?? []
            let useSession = args["use_session"] as? Bool ?? false
            
            return await PlaywrightRunner.run(url: url, actions: actions, useSession: useSession)
        }
    )
}

enum PlaywrightRunner {
    static func run(url: String, actions: [[String: Any]], useSession: Bool) async -> String {
        // 1. Prepare dynamic paths
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let sessionsDir = appSupport.appendingPathComponent("AgentKVT/browser_sessions", isDirectory: true)
        
        let urlObj = URL(string: url)
        let domain = urlObj?.host ?? "unknown"
        let storageStatePath = useSession ? sessionsDir.appendingPathComponent("\(domain).json").path : nil
        
        // 2. Prepare JSON input for the Node.js script
        let input: [String: Any] = [
            "url": url,
            "actions": actions,
            "storageStatePath": storageStatePath as Any,
            "timeout": 45000
        ]
        
        guard let inputData = try? JSONSerialization.data(withJSONObject: input),
              let inputString = String(data: inputData, encoding: .utf8) else {
            return "Error: Failed to encode input for SiteScout."
        }
        
        // 3. Locate the Node.js binary and script
        // Note: For development, we assume node is in the path or we look in common locations.
        // In production, the app should package node or require it in a specific path.
        let nodePath = findNodeBinary() ?? "/usr/local/bin/node"
        
        // Find the script relative to the runner or in the project structure
        // This path needs to be robust for both local dev and production builds.
        let scriptPath = findScriptPath() ?? "Scouts/site-scout.js"
        
        // 4. Run the process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [scriptPath]
        
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            try inputPipe.fileHandleForWriting.write(contentsOf: inputData)
            try inputPipe.fileHandleForWriting.close()
            
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            if process.terminationStatus != 0 {
                let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                return "Error (Exit \(process.terminationStatus)): \(errorString)"
            }
            
            return String(data: outputData, encoding: .utf8) ?? "Done (No output)"
            
        } catch {
            return "Error launching SiteScout: \(error.localizedDescription)"
        }
    }
    
    private static func findNodeBinary() -> String? {
        let paths = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    private static func findScriptPath() -> String? {
        // Look for the script in the current directory or Resources
        let localPath = "Scouts/site-scout.js"
        if FileManager.default.fileExists(atPath: localPath) {
            return localPath
        }
        // In a deployed app context, it might be in the bundle resources.
        return Bundle.main.path(forResource: "site-scout", ofType: "js")
    }
}
