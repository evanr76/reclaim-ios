import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Live Activity describing the scheduled block happening right now — rendered
/// on the Lock Screen and in the Dynamic Island. Shared between the app (which
/// starts/updates/ends it) and the widget extension (which renders it).
public struct FocusBlockAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var title: String
        public var endDate: Date
        public var priority: String?

        public init(title: String, endDate: Date, priority: String?) {
            self.title = title
            self.endDate = endDate
            self.priority = priority
        }
    }

    public var startDate: Date

    public init(startDate: Date) { self.startDate = startDate }
}
#endif
