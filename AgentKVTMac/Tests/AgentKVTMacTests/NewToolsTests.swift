import Foundation
import Testing
@testable import AgentKVTMac

// MARK: - ReadLocalFileTool Tests

@Suite("ReadLocalFileTool Tests")
struct ReadLocalFileToolTests {

    @Test("reads a valid txt file within allowed directory")
    func readValidTxtFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("notes.txt")
        try "Hello from test".write(to: file, atomically: true, encoding: .utf8)

        let result = ReadLocalFileToolHandler.read(rawPath: file.path, allowedDirectories: [dir])
        #expect(result == "Hello from test")
    }

    @Test("reads a valid csv file within allowed directory")
    func readValidCsvFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("data.csv")
        try "a,b,c\n1,2,3".write(to: file, atomically: true, encoding: .utf8)

        let result = ReadLocalFileToolHandler.read(rawPath: file.path, allowedDirectories: [dir])
        #expect(result.contains("a,b,c"))
    }

    @Test("rejects path outside allowed directories")
    func rejectPathOutsideAllowed() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = ReadLocalFileToolHandler.read(rawPath: "/etc/passwd", allowedDirectories: [dir])
        #expect(result.hasPrefix("Error:"))
        #expect(result.contains("outside allowed"))
    }

    @Test("returns error for missing file within allowed directory")
    func missingFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = ReadLocalFileToolHandler.read(
            rawPath: dir.appendingPathComponent("nonexistent.txt").path,
            allowedDirectories: [dir]
        )
        #expect(result.contains("Error:"))
        #expect(result.contains("not found"))
    }

    @Test("returns error for unsupported file extension")
    func unsupportedExtension() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("binary.bin")
        try Data([0x00, 0x01]).write(to: file)

        let result = ReadLocalFileToolHandler.read(rawPath: file.path, allowedDirectories: [dir])
        #expect(result.contains("Error:"))
        #expect(result.contains("Unsupported file type"))
    }

    @Test("returns error when no allowed directories configured")
    func noAllowedDirectories() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("notes.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)

        let result = ReadLocalFileToolHandler.read(rawPath: file.path, allowedDirectories: [])
        #expect(result.contains("Error:"))
        #expect(result.contains("outside allowed"))
    }

    @Test("returns error for directory path instead of file")
    func directoryPath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Allow the parent temp dir so the directory itself passes the allowlist check
        let parent = dir.deletingLastPathComponent()
        let result = ReadLocalFileToolHandler.read(rawPath: dir.path, allowedDirectories: [parent])
        #expect(result.contains("Error:"))
        #expect(result.contains("directory"))
    }

    @Test("makeReadLocalFileTool has correct id and name")
    func toolMetadata() {
        let dir = FileManager.default.temporaryDirectory
        let tool = makeReadLocalFileTool(allowedDirectories: [dir])
        #expect(tool.id == "read_local_file")
        #expect(tool.name == "read_local_file")
    }

    @Test("makeReadLocalFileTool returns error when path arg missing")
    func toolMissingPath() async throws {
        let tool = makeReadLocalFileTool(allowedDirectories: [])
        let result = try await tool.handler([:])
        #expect(result.contains("Error:"))
        #expect(result.contains("path is required"))
    }
}

// MARK: - ShellCommandTool Tests

@Suite("ShellCommandTool Tests")
struct ShellCommandToolTests {

    @Test("returns error for unknown command id")
    func unknownCommandId() {
        let result = ShellCommandToolHandler.run(commandId: "rm_rf_slash")
        #expect(result.hasPrefix("Error:"))
        #expect(result.contains("Unknown command"))
    }

    @Test("date command returns non-empty output")
    func dateCommand() {
        let result = ShellCommandToolHandler.run(commandId: "date")
        #expect(!result.hasPrefix("Error:"))
        #expect(!result.isEmpty)
    }

    @Test("uptime command returns non-empty output")
    func uptimeCommand() {
        let result = ShellCommandToolHandler.run(commandId: "uptime")
        #expect(!result.hasPrefix("Error:"))
        #expect(!result.isEmpty)
    }

    @Test("sw_version command returns macOS version info")
    func swVersionCommand() {
        let result = ShellCommandToolHandler.run(commandId: "sw_version")
        #expect(!result.hasPrefix("Error:"))
        #expect(result.contains("macOS") || result.contains("ProductVersion") || result.contains("ProductName"))
    }

    @Test("disk_usage command returns non-empty output")
    func diskUsageCommand() {
        let result = ShellCommandToolHandler.run(commandId: "disk_usage")
        #expect(!result.hasPrefix("Error:"))
        #expect(!result.isEmpty)
    }

    @Test("makeShellCommandTool has correct id and name")
    func toolMetadata() {
        let tool = makeShellCommandTool()
        #expect(tool.id == "run_shell_command")
        #expect(tool.name == "run_shell_command")
    }

    @Test("makeShellCommandTool returns error for missing command arg")
    func toolMissingCommand() async throws {
        let tool = makeShellCommandTool()
        let result = try await tool.handler([:])
        #expect(result.contains("Error:"))
        #expect(result.contains("command is required"))
    }

    @Test("makeShellCommandTool rejects unknown command via handler")
    func toolUnknownCommand() async throws {
        let tool = makeShellCommandTool()
        let result = try await tool.handler(["command": "sudo_make_me_a_sandwich"])
        #expect(result.hasPrefix("Error:"))
        #expect(result.contains("Unknown command"))
    }
}
