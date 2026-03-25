import CoreData
import Foundation

/// Watches the shared CloudKit-backed persistent store for remote changes pushed from iOS.
///
/// When the iPhone's EdgeSummarizationService inserts a new `IncomingEmailSummary` and
/// CloudKit delivers it to the Mac, `NSPersistentStoreCoordinator` posts
/// `NSPersistentStoreRemoteChangeNotification`. This observer catches that signal and
/// fires `onRemoteChange` so the execution queue can schedule a `.cloudKitSync` work item.
///
/// **No ModelContext here.** The notification fires on an arbitrary background thread;
/// we do not touch SwiftData from this callback. The actual fetch happens inside the
/// actor-isolated `MissionExecutionQueue.dispatch(.cloudKitSync)`, which runs on the
/// actor's serial executor where the ModelContext lives safely.
///
/// **Activation:** `NSPersistentStoreRemoteChangeNotification` is only posted when
/// `NSPersistentStoreRemoteChangeNotificationPostOptionKey = true` is set on the store.
/// `NSPersistentCloudKitContainer` (which SwiftData uses for CloudKit backends) sets this
/// automatically — no extra setup required.
final class CloudKitObserver {

    // MARK: - State

    private var observerToken: (any NSObjectProtocol)?
    private let onRemoteChange: () -> Void

    // MARK: - Init

    /// - Parameter onRemoteChange: Called on a background thread when CloudKit delivers
    ///   remote changes. Must be cheap and non-blocking. Typically: `Task { await queue.enqueue(.cloudKitSync) }`.
    init(onRemoteChange: @escaping () -> Void) {
        self.onRemoteChange = onRemoteChange
    }

    deinit { stop() }

    // MARK: - Lifecycle

    func start() {
        guard observerToken == nil else { return }
        // NSPersistentStoreRemoteChangeNotification is the canonical notification posted
        // by NSPersistentCloudKitContainer when CloudKit delivers remote store changes.
        // Observing with object: nil catches it for all stores (we only have one).
        let name = Notification.Name("NSPersistentStoreRemoteChangeNotification")
        observerToken = NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: nil  // nil = deliver on the posting thread (background, that's fine)
        ) { [weak self] notification in
            guard let self else { return }
            let storeName = (notification.userInfo?["NSPersistentStoreName"] as? String) ?? "unknown"
            print("[CloudKitObserver] Remote change on store '\(storeName)' — enqueueing cloudKitSync.")
            self.onRemoteChange()
        }
        print("[CloudKitObserver] Started — listening for NSPersistentStoreRemoteChangeNotification.")
    }

    func stop() {
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
            observerToken = nil
        }
    }
}
