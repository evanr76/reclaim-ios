import Foundation
import ActivityKit
import ReclaimKit

/// Starts / updates / ends the focus-block Live Activity based on the current
/// scheduled moment. Called from the view model after each refresh.
@MainActor
enum LiveActivityManager {
    /// In-process timer that ends the activity exactly at the block's end while
    /// the app is alive. There is no push-free way to remove a Live Activity at a
    /// precise time *once the app is suspended*, so this covers the foreground
    /// case; `endStaleActivities()` on every foreground and the widget's "Ended"
    /// stale rendering handle the suspended case.
    private static var autoEndTask: Task<Void, Never>?

    /// End any Live Activity whose block has already ended. Uses the activity's
    /// own `endDate`, so it works even if the app was suspended when the block
    /// ended and the moment data is stale/unavailable. Call on app launch and on
    /// every foreground.
    static func endStaleActivities() {
        let now = Date()
        for activity in Activity<FocusBlockAttributes>.activities where activity.content.state.endDate <= now {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    static func sync(current: MomentEvent?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        endStaleActivities()

        let active = current.flatMap { c -> (MomentEvent, Date)? in
            guard c.isActive(), let end = c.eventEnd, end > Date() else { return nil }
            return (c, end)
        }

        guard let (event, end) = active else {
            // No block running now — cancel any pending auto-end and end existing.
            autoEndTask?.cancel()
            autoEndTask = nil
            for activity in Activity<FocusBlockAttributes>.activities {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }

        let state = FocusBlockAttributes.ContentState(
            title: event.displayTitle, endDate: end, priority: event.priority
        )
        let content = ActivityContent(state: state, staleDate: end)

        if let existing = Activity<FocusBlockAttributes>.activities.first {
            Task { await existing.update(content) }
        } else {
            do {
                _ = try Activity.request(
                    attributes: FocusBlockAttributes(startDate: event.eventStart ?? Date()),
                    content: content,
                    pushType: nil
                )
            } catch {
                // Activities disabled or over the limit — ignore.
            }
        }

        scheduleAutoEnd(at: end)
    }

    /// Remove the activity exactly at `end` — but only fires while the app is
    /// still running (a suspended app's tasks are frozen; foreground cleanup
    /// catches those). Replaces any previously scheduled end.
    private static func scheduleAutoEnd(at end: Date) {
        autoEndTask?.cancel()
        let seconds = end.timeIntervalSinceNow
        guard seconds > 0 else { endStaleActivities(); return }
        autoEndTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            endStaleActivities()
        }
    }
}
