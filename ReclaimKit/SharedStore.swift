import Foundation

/// Shared App Group storage so the widget can render the "Up Next" glance
/// without needing the token or network — the app writes a small snapshot
/// after each refresh; the widget reads it.
public enum SharedStore {
    public static let appGroup = "group.io.github.evanr76.reclaimios"
    private static let snapshotKey = "upNextSnapshot"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// A trimmed task representation for the widget.
    public struct TaskSnapshot: Codable, Identifiable, Hashable {
        public let id: Int
        public let title: String
        public let priority: String?
        public let dueDate: Date?
        public let onDeck: Bool
        public let overdue: Bool

        public init(id: Int, title: String, priority: String?, dueDate: Date?, onDeck: Bool, overdue: Bool) {
            self.id = id
            self.title = title
            self.priority = priority
            self.dueDate = dueDate
            self.onDeck = onDeck
            self.overdue = overdue
        }
    }

    public static func saveSnapshot(_ tasks: [TaskSnapshot]) {
        guard let defaults, let data = try? JSONEncoder().encode(tasks) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    public static func loadSnapshot() -> [TaskSnapshot] {
        guard let defaults,
              let data = defaults.data(forKey: snapshotKey),
              let tasks = try? JSONDecoder().decode([TaskSnapshot].self, from: data)
        else { return [] }
        return tasks
    }
}

public extension ReclaimTask {
    /// Build a widget snapshot row from a full task.
    var snapshot: SharedStore.TaskSnapshot {
        SharedStore.TaskSnapshot(
            id: id,
            title: displayTitle,
            priority: priority,
            dueDate: due,
            onDeck: onDeck ?? false,
            overdue: isOverdue
        )
    }
}
