import Foundation
import SwiftUI

/// Persists which family profile is active on this device (`UserDefaults`, per-device preference).
public final class FamilyProfileStore: ObservableObject {
    private let defaultsKey = "agentkvt.currentProfileId"

    @Published public var currentProfileId: UUID? {
        didSet {
            if let id = currentProfileId {
                UserDefaults.standard.set(id.uuidString, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }
    }

    public init() {
        if let s = UserDefaults.standard.string(forKey: defaultsKey),
           let u = UUID(uuidString: s) {
            currentProfileId = u
        } else {
            currentProfileId = nil
        }
    }

    public func hasValidSelection(memberIDs: [UUID]) -> Bool {
        guard let id = currentProfileId else { return false }
        return memberIDs.contains(id)
    }

    public func selectProfile(_ id: UUID) {
        currentProfileId = id
    }

    public func clearSelection() {
        currentProfileId = nil
    }
}
