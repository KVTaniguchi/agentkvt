import Foundation

/// Allowed shell commands: maps a stable command ID to a fixed (executable, args) pair.
/// The LLM picks a command ID only — no LLM-controlled arguments are accepted,
/// preventing argument injection while still exposing useful read-only diagnostics.
private let shellCommandAllowlist: [String: (executable: String, args: [String], description: String)] = [
    "date":          ("/bin/date",                   [],                       "Current date and time"),
    "uptime":        ("/usr/bin/uptime",              [],                       "System uptime and load averages"),
    "disk_usage":    ("/bin/df",                      ["-h", "/"],              "Disk usage for the root volume"),
    "sw_version":    ("/usr/bin/sw_vers",             [],                       "macOS software version"),
    "brew_list":     ("/opt/homebrew/bin/brew",       ["list", "--formula"],    "Installed Homebrew formulas"),
    "brew_outdated": ("/opt/homebrew/bin/brew",       ["outdated"],             "Outdated Homebrew packages"),
    "who":           ("/usr/bin/who",                 [],                       "Currently logged-in users"),
    "memory_usage":  ("/usr/bin/vm_stat",             [],                       "Virtual memory statistics"),
]

/// Create a tool that runs a fixed set of read-only shell diagnostics.
/// The LLM can only choose a command from the allowlist by ID; no arbitrary shell input is accepted.
public func makeShellCommandTool() -> ToolRegistry.Tool {
    let allowlistDescription = shellCommandAllowlist
        .sorted { $0.key < $1.key }
        .map { "'\($0.key)': \($0.value.description)" }
        .joined(separator: "; ")

    return ToolRegistry.Tool(
        id: "run_shell_command",
        name: "run_shell_command",
        description: """
            Run a read-only system diagnostic command from a fixed allowlist.
            Use this to check system state (disk space, uptime, software version, etc.) when relevant to a mission.
            Available commands: \(allowlistDescription)
            """,
        parameters: .init(
            type: "object",
            properties: [
                "command": .init(
                    type: "string",
                    description: "The command ID to run. Must be one of: \(shellCommandAllowlist.keys.sorted().joined(separator: ", "))."
                )
            ],
            required: ["command"]
        ),
        handler: { args in
            guard let commandId = args["command"] as? String,
                  !commandId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "Error: command is required."
            }
            return ShellCommandToolHandler.run(commandId: commandId.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    )
}

enum ShellCommandToolHandler {
    static func run(commandId: String) -> String {
        guard let entry = shellCommandAllowlist[commandId] else {
            let valid = shellCommandAllowlist.keys.sorted().joined(separator: ", ")
            return "Error: Unknown command '\(commandId)'. Valid commands: \(valid)"
        }

        guard FileManager.default.isExecutableFile(atPath: entry.executable) else {
            return "Error: '\(entry.executable)' not found or not executable on this system."
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: entry.executable)
        process.arguments = entry.args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "Error running '\(commandId)': \(error.localizedDescription)"
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return "(no output)"
        }
        return String(trimmed.prefix(8_000))
    }
}
