import Foundation
import Testing
@testable import ManagerCore

/// iOS app unit tests: validate the ManagerCore data layer used by the app.
struct ManagerCoreIntegrationTests {

    @Test("LifeContext key-value used by Context tab")
    func lifeContextKeyValue() {
        let ctx = LifeContext(key: "goals", value: "Ship v1")
        #expect(ctx.key == "goals")
        #expect(ctx.value == "Ship v1")
    }
}
