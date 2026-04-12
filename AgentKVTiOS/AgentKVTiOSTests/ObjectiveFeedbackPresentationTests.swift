import Foundation
import Testing
@testable import AgentKVTiOS

@Suite("Objective feedback presentation")
struct ObjectiveFeedbackPresentationTests {
    private let objectiveID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let taskID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let timestamp = Date(timeIntervalSince1970: 1_744_467_200)

    @Test("Task summary snapshots use the linked task description")
    func taskSummarySnapshotsUseLinkedTaskDescription() {
        let task = IOSBackendTask(
            id: taskID,
            objectiveId: objectiveID,
            sourceFeedbackId: nil,
            description: "Compare Slack and email signal quality for inbound alerts",
            status: "completed",
            resultSummary: "Slack is fastest but email has better audit trail.",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let snapshot = IOSBackendResearchSnapshot(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            objectiveId: objectiveID,
            taskId: taskID,
            key: "task_summary_8c43a5f1d2e3",
            value: "Slack surfaced alerts faster in three of three checks.",
            previousValue: nil,
            deltaNote: nil,
            checkedAt: timestamp,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let label = ObjectiveFeedbackPresentation.targetLabel(for: snapshot, tasks: [task])

        #expect(label == "Finding: Compare Slack and email signal quality for inbound alerts")
    }

    @Test("Normal findings keep their snapshot-based label")
    func normalFindingsKeepSnapshotLabel() {
        let snapshot = IOSBackendResearchSnapshot(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            objectiveId: objectiveID,
            taskId: taskID,
            key: "slack_signal",
            value: "Webhook delivery succeeded within 4 seconds.",
            previousValue: nil,
            deltaNote: nil,
            checkedAt: timestamp,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let label = ObjectiveFeedbackPresentation.targetLabel(for: snapshot)

        #expect(label == "Finding: Slack signal")
    }

    @Test("Task summary snapshots fall back to the key when the task is missing")
    func taskSummarySnapshotsFallBackWhenTaskMissing() {
        let snapshot = IOSBackendResearchSnapshot(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            objectiveId: objectiveID,
            taskId: taskID,
            key: "task_summary_c1e2f3a4b5c6",
            value: "Fallback should stay readable.",
            previousValue: nil,
            deltaNote: nil,
            checkedAt: timestamp,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let label = ObjectiveFeedbackPresentation.targetLabel(for: snapshot, tasks: [])

        #expect(label == "Finding: Task summary c1e2f3a4b5c6")
    }

    @Test("Display text strips the confidence options appendix")
    func displayTextStripsConfidenceOptionsAppendix() {
        let text = """
        Confidence: low - official park hours changed twice this week.
        Early entry might apply, but the policy still looks inconsistent across sources.

        Confidence options:
        - Verify the current July 11 park hours on the official Universal site.
        - Compare this finding against the strongest realistic backup plan.
        """

        let body = ObjectiveFeedbackPresentation.displayText(text)
        let options = ObjectiveFeedbackPresentation.confidenceOptionLabels(in: text)

        #expect(body == """
        Confidence: low - official park hours changed twice this week.
        Early entry might apply, but the policy still looks inconsistent across sources.
        """)
        #expect(options.count == 2)
        #expect(options[0] == "Verify the current July 11 park hours on the official Universal site.")
    }

    @Test("Low confidence snapshots without explicit options still get fallback actions")
    func lowConfidenceSnapshotsGetFallbackActions() {
        let snapshot = IOSBackendResearchSnapshot(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            objectiveId: objectiveID,
            taskId: taskID,
            key: "park_hours",
            value: "Confidence: low - official and third-party sources disagree on early entry.",
            previousValue: nil,
            deltaNote: nil,
            checkedAt: timestamp,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let options = ObjectiveConfidenceOptionBuilder.options(for: snapshot)

        #expect(options.count == 3)
        #expect(options[0].feedbackKind == .challengeResult)
        #expect(options[1].feedbackKind == .compareOptions)
    }
}
