import Foundation
import SwiftUI
import ManagerCore

/// Persists which `FamilyMember` is active on this device (`UserDefaults`, not CloudKit — per-device preference).
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

    public func hasValidSelection(members: [FamilyMember]) -> Bool {
        guard let id = currentProfileId else { return false }
        return members.contains { $0.id == id }
    }

    public func selectProfile(_ id: UUID) {
        currentProfileId = id
    }

    public func clearSelection() {
        currentProfileId = nil
    }
}
