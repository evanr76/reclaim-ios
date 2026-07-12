import Foundation
import AppIntents
import WidgetKit

/// Completes a task straight from the widget. Widget button intents run in the
/// app's process, so this reads the token from the app's Keychain (no token
/// sharing needed) and optimistically updates the shared snapshot.
public struct CompleteTaskIntent: AppIntent {
    public static let title: LocalizedStringResource = "Complete Reclaim Task"
    public static let isDiscoverable = false   // widget-only, not surfaced in Shortcuts

    @Parameter(title: "Task ID")
    public var taskId: Int

    public init() {}
    public init(taskId: Int) { self.taskId = taskId }

    public func perform() async throws -> some IntentResult {
        guard let token = KeychainStore.readToken() else { return .result() }
        try await ReclaimAPIClient(token: token).markComplete(id: taskId)
        // Optimistically drop it from the widget snapshot and refresh.
        var snapshot = SharedStore.loadSnapshot()
        snapshot.removeAll { $0.id == taskId }
        SharedStore.saveSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
