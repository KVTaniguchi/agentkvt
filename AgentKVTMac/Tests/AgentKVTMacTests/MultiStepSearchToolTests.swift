import Foundation
import Testing
@testable import AgentKVTMac

@Test("MultiStepSearch routes browse steps through the direct browse executor")
func multiStepSearchRoutesBrowseStepsThroughDirectExecutor() async throws {
    final class CaptureBox: @unchecked Sendable {
        var searchQueries: [String] = []
        var browseURLs: [String] = []
        var browseActions: [String?] = []
        var browseSelectors: [String?] = []
    }

    let box = CaptureBox()
    let tool = makeMultiStepSearchTool(
        apiKey: "test-api-key",
        searchExecutor: { query, _, _ in
            box.searchQueries.append(query)
            return "SEARCH:\(query)"
        },
        browseExecutor: { url, actionsJson, extractSelector, _ in
            box.browseURLs.append(url)
            box.browseActions.append(actionsJson)
            box.browseSelectors.append(extractSelector)
            return "BROWSE:\(url)"
        }
    )

    let steps = """
    [
      {"type":"search","query":"best family flights"},
      {"type":"browse","url":"https://example.com/rates","actions_json":"[{\\\"type\\\":\\\"click\\\"}]","extract_selector":"main"}
    ]
    """
    let result = try await tool.handler(["steps_json": steps])

    #expect(box.searchQueries == ["best family flights"])
    #expect(box.browseURLs == ["https://example.com/rates"])
    #expect(box.browseActions == ["[{\"type\":\"click\"}]"])
    #expect(box.browseSelectors == ["main"])
    #expect(result.contains("SEARCH:best family flights"))
    #expect(result.contains("BROWSE:https://example.com/rates"))
}
