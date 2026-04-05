import Foundation
import SwiftData
import Testing
@testable import ManagerCore

/// iOS app unit tests: validate the ManagerCore data layer used by the app.
struct ManagerCoreIntegrationTests {

    @Test("ActionItem unhandled items are shown in Actions tab")
    func actionItemUnhandled() {
        let item = ActionItem(title: "Review job", systemIntent: SystemIntent.urlOpen.rawValue)
        #expect(item.isHandled == false)
        item.isHandled = true
        #expect(item.isHandled == true)
    }

    @Test("LifeContext key-value used by Context tab")
    func lifeContextKeyValue() {
        let ctx = LifeContext(key: "goals", value: "Ship v1")
        #expect(ctx.key == "goals")
        #expect(ctx.value == "Ship v1")
    }
}
