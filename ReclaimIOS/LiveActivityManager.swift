import Foundation
import ActivityKit
import ReclaimKit

/// Starts / updates / ends the focus-block Live Activity based on the current
/// scheduled moment. Called from the view model after each refresh.
@MainActor
enum LiveActivityManager {
    static func sync(current: MomentEvent?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let active = current.flatMap { c -> (MomentEvent, Date)? in
            guard c.isActive(), let end = c.eventEnd else { return nil }
            return (c, end)
        }

        guard let (event, end) = active else {
            // No block running now — end any existing activity.
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
    }
}
