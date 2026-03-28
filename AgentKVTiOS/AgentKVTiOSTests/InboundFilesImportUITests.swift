import Testing
@testable import AgentKVTiOS

struct InboundFilesImportUITests {

    @Test("Inbound Files add control uses a stable accessibility identifier for UI tests")
    func addButtonAccessibilityIdentifier() {
        #expect(InboundFilesImportUI.addButtonAccessibilityIdentifier == "inbound-files-add-items")
    }
}
