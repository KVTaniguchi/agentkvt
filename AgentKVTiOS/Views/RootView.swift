import SwiftUI
import SwiftData
import ManagerCore

/// Routes between onboarding, profile selection, and the main dashboard.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyMember.createdAt, order: .forward) private var members: [FamilyMember]
    @EnvironmentObject private var profileStore: FamilyProfileStore

    var body: some View {
        Group {
            if members.isEmpty {
                FamilyOnboardingView(profileStore: profileStore)
            } else if !profileStore.hasValidSelection(members: members) {
                ProfilePickerView(members: members, profileStore: profileStore)
            } else {
                DashboardView()
            }
        }
    }
}
