import SwiftData

/// Explicit wrapper for the runner's intentionally serialized SwiftData context.
/// This avoids retroactive Sendable conformances on SwiftData types while making
/// actor boundaries obvious in the call sites that opt into them.
struct SharedModelContext: @unchecked Sendable {
    let raw: ModelContext

    init(_ raw: ModelContext) {
        self.raw = raw
    }
}
