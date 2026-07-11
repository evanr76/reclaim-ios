import AppIntents
import Foundation
import ReclaimKit

extension Notification.Name {
    static let reclaimTaskCreated = Notification.Name("ReclaimTaskCreated")
}

enum TaskPriorityAppEnum: String, AppEnum {
    case highest, high, normal, low
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Priority"
    static let caseDisplayRepresentations: [TaskPriorityAppEnum: DisplayRepresentation] = [
        .highest: "P1 — Highest", .high: "P2 — High", .normal: "P3 — Medium", .low: "P4 — Low",
    ]
    var toPriority: Priority {
        switch self {
        case .highest: return .p1
        case .high: return .p2
        case .normal: return .p3
        case .low: return .p4
        }
    }
}

enum ReclaimIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notConfigured
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notConfigured: return "Open Reclaim and add your API key before adding tasks by voice."
        }
    }
}

struct AddReclaimTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Reclaim Task"
    static let description = IntentDescription("Create a new task in Reclaim.")
    static let openAppWhenRun = false

    @Parameter(title: "Task", requestValueDialog: "What's the task?")
    var taskTitle: String

    @Parameter(title: "Priority", default: .normal)
    var priority: TaskPriorityAppEnum

    @Parameter(title: "Duration (hours)", default: 1.0, inclusiveRange: (0.25, 40.0))
    var durationHours: Double

    @Parameter(title: "Due Date")
    var due: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$taskTitle) to Reclaim") {
            \.$priority
            \.$durationHours
            \.$due
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let token = KeychainStore.readToken() else { throw ReclaimIntentError.notConfigured }
        let client = ReclaimAPIClient(token: token)
        let created = try await client.createTask(
            title: taskTitle, priority: priority.toPriority, durationHours: durationHours, due: due
        )
        NotificationCenter.default.post(name: .reclaimTaskCreated, object: nil)
        return .result(dialog: "Added “\(created.displayTitle)” to Reclaim.")
    }
}

struct ReclaimShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddReclaimTaskIntent(),
            phrases: [
                "Add a task to \(.applicationName)",
                "Add a \(.applicationName) task",
                "Create a \(.applicationName) task",
                "New task in \(.applicationName)",
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle.fill"
        )
    }
}
