import Foundation
import Testing
@testable import AgentKVTMac

struct ToolRegistryTests {

    @Test("register and retrieve tool by id")
    func registerAndRetrieve() {
        let registry = ToolRegistry()
        let tool = ToolRegistry.Tool(
            id: "echo",
            name: "echo",
            description: "Echo back the input",
            parameters: .init(type: "object", properties: ["msg": .init(type: "string", description: "Message")], required: ["msg"]),
            handler: { args in
                let msg = args["msg"] as? String ?? ""
                return "Echo: \(msg)"
            }
        )
        registry.register(tool)
        let retrieved = registry.tool(id: "echo")
        #expect(retrieved != nil)
        #expect(retrieved?.id == "echo")
        #expect(retrieved?.name == "echo")
    }

    @Test("toolIds returns sorted registered ids")
    func toolIdsSorted() {
        let registry = ToolRegistry()
        registry.register(ToolRegistry.Tool(id: "z_last", name: "z_last", description: nil, parameters: nil) { _ in "ok" })
        registry.register(ToolRegistry.Tool(id: "a_first", name: "a_first", description: nil, parameters: nil) { _ in "ok" })
        let ids = registry.toolIds()
        #expect(ids == ["a_first", "z_last"])
    }

    @Test("ollamaToolDefs returns only allowed tool ids")
    func ollamaToolDefsFiltersByAllowed() {
        let registry = ToolRegistry()
        registry.register(ToolRegistry.Tool(id: "allowed", name: "allowed", description: "Allowed", parameters: nil) { _ in "ok" })
        registry.register(ToolRegistry.Tool(id: "forbidden", name: "forbidden", description: "Forbidden", parameters: nil) { _ in "ok" })
        let defs = registry.ollamaToolDefs(allowedIds: ["allowed"])
        #expect(defs.count == 1)
        #expect(defs[0].function.name == "allowed")
    }

    @Test("execute runs handler when tool is allowed")
    func executeWhenAllowed() async throws {
        let registry = ToolRegistry()
        registry.register(ToolRegistry.Tool(
            id: "add",
            name: "add",
            description: nil,
            parameters: nil
        ) { args in
            let a = args["a"] as? Int ?? 0
            let b = args["b"] as? Int ?? 0
            return "\(a + b)"
        })
        let result = try await registry.execute(name: "add", arguments: #"{"a":2,"b":3}"#, allowedIds: ["add"])
        #expect(result == "5")
    }

    @Test("execute throws toolNotAllowed when id not in allowedIds")
    func executeThrowsWhenNotAllowed() async {
        let registry = ToolRegistry()
        registry.register(ToolRegistry.Tool(id: "secret", name: "secret", description: nil, parameters: nil) { _ in "no" })
        do {
            _ = try await registry.execute(name: "secret", arguments: "{}", allowedIds: ["other"])
            #expect(Bool(false), "Expected toolNotAllowed to be thrown")
        } catch let err as ToolRegistryError {
            if case .toolNotAllowed("secret") = err { return }
            Issue.record("Expected toolNotAllowed(secret), got \(err)")
        } catch {
            Issue.record("Expected ToolRegistryError, got \(error)")
        }
    }

    @Test("execute throws unknownTool for unregistered name")
    func executeThrowsUnknownTool() async {
        let registry = ToolRegistry()
        do {
            _ = try await registry.execute(name: "nonexistent", arguments: "{}", allowedIds: ["nonexistent"])
            #expect(Bool(false), "Expected unknownTool to be thrown")
        } catch let err as ToolRegistryError {
            if case .unknownTool("nonexistent") = err { return }
            Issue.record("Expected unknownTool(nonexistent), got \(err)")
        } catch {
            Issue.record("Expected ToolRegistryError, got \(error)")
        }
    }
}
