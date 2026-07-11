import SwiftUI
import Observation
import Network
import WidgetKit
import ReclaimKit

/// Which slice of tasks to show.
enum TaskFilter: String, CaseIterable, Identifiable {
    case active = "Active"
    case overdue = "Overdue"
    case completed = "Completed"
    case all = "All"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .active: return "circle"
        case .overdue: return "exclamationmark.triangle"
        case .completed: return "checkmark.circle"
        case .all: return "tray.full"
        }
    }
}

/// App state: auth/token, the task list, filters, and every mutating operation.
@MainActor
@Observable
final class TaskListViewModel {
    private(set) var isConfigured = false
    private(set) var user: ReclaimUser?
    private var client: ReclaimAPIClient?

    private(set) var allTasks: [ReclaimTask] = []
    private(set) var lastRefreshed: Date?

    var filter: TaskFilter = .active
    var searchText: String = ""
    private(set) var isLoading = false
    private(set) var isBusy = false
    var errorMessage: String?
    var statusMessage: String?

    private(set) var isOnline = true
    private let pathMonitor = NWPathMonitor()
    private var refreshTask: Task<Void, Never>?

    init() {
        if let token = KeychainStore.readToken() {
            client = ReclaimAPIClient(token: token)
            isConfigured = true
        }
        #if DEBUG
        // Simulator convenience: inject a token via the RECLAIM_TOKEN env var.
        if client == nil, let env = ProcessInfo.processInfo.environment["RECLAIM_TOKEN"], !env.isEmpty {
            client = ReclaimAPIClient(token: env)
            isConfigured = true
        }
        #endif
        NotificationCenter.default.addObserver(
            forName: .reclaimTaskCreated, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.loadTasks() }
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOnline = (path.status == .satisfied) }
        }
        pathMonitor.start(queue: DispatchQueue.global(qos: .utility))
        let stored = UserDefaults.standard.object(forKey: "refreshIntervalMinutes") as? Int ?? 60
        configureAutoRefresh(intervalMinutes: stored)
    }

    func configureAutoRefresh(intervalMinutes: Int) {
        refreshTask?.cancel()
        guard intervalMinutes > 0 else { refreshTask = nil; return }
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double(intervalMinutes) * 60))
                guard let self, !Task.isCancelled else { break }
                if self.isOnline && self.isConfigured { await self.loadTasks(silent: true) }
            }
        }
    }

    // MARK: - Derived lists

    var filteredTasks: [ReclaimTask] {
        let base: [ReclaimTask]
        switch filter {
        case .active: base = allTasks.filter { !$0.isFinished }
        case .overdue: base = allTasks.filter { $0.isOverdue }
        case .completed: base = allTasks.filter { $0.isFinished }
        case .all: base = allTasks
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let searched = query.isEmpty ? base : base.filter {
            $0.displayTitle.lowercased().contains(query) || ($0.notes?.lowercased().contains(query) ?? false)
        }
        return searched.sorted(by: Self.defaultSort)
    }

    var upNextTasks: [ReclaimTask] { filteredTasks.filter { $0.onDeck == true } }
    var otherTasks: [ReclaimTask] { filteredTasks.filter { !($0.onDeck ?? false) } }

    /// Up Next + highest-priority unfinished, capped at 5 — used for the widget snapshot.
    var glanceTasks: [ReclaimTask] {
        let unfinished = allTasks.filter { !$0.isFinished }
        let upNext = unfinished.filter { $0.onDeck == true }.sorted(by: Self.defaultSort)
        let others = unfinished.filter { !($0.onDeck ?? false) }.sorted { a, b in
            let pa = a.priorityEnum ?? .p3, pb = b.priorityEnum ?? .p3
            if pa != pb { return pa < pb }
            return Self.defaultSort(a, b)
        }
        return Array((upNext + others).prefix(5))
    }

    func count(for filter: TaskFilter) -> Int {
        switch filter {
        case .active: return allTasks.filter { !$0.isFinished }.count
        case .overdue: return allTasks.filter { $0.isOverdue }.count
        case .completed: return allTasks.filter { $0.isFinished }.count
        case .all: return allTasks.count
        }
    }

    static func defaultSort(_ a: ReclaimTask, _ b: ReclaimTask) -> Bool {
        switch (a.due, b.due) {
        case let (da?, db?) where da != db: return da < db
        case (nil, .some): return false
        case (.some, nil): return true
        default: break
        }
        let pa = a.priorityEnum ?? .p3
        let pb = b.priorityEnum ?? .p3
        if pa != pb { return pa < pb }
        return a.id < b.id
    }

    func task(withID id: Int) -> ReclaimTask? { allTasks.first { $0.id == id } }

    // MARK: - Auth

    func saveToken(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMessage = "Please enter your Reclaim API key."; return }
        let candidate = ReclaimAPIClient(token: trimmed)
        isBusy = true
        defer { isBusy = false }
        do {
            let me = try await candidate.currentUser()
            guard KeychainStore.saveToken(trimmed) else { errorMessage = "Could not save the key to the Keychain."; return }
            client = candidate
            user = me
            isConfigured = true
            errorMessage = nil
            statusMessage = "Connected as \(me.displayName)."
            await loadTasks()
        } catch {
            errorMessage = (error as? ReclaimAPIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    func signOut() {
        KeychainStore.deleteToken()
        client = nil
        user = nil
        isConfigured = false
        allTasks = []
        lastRefreshed = nil
        publishSnapshot()
        statusMessage = "Signed out."
    }

    // MARK: - Loading

    func loadTasks(silent: Bool = false) async {
        guard let client else { isConfigured = false; return }
        if !silent { isLoading = true }
        defer { if !silent { isLoading = false } }
        do {
            if user == nil { user = try await client.currentUser() }
            guard let userId = user?.id else {
                if !silent { errorMessage = "Could not determine the current user." }
                return
            }
            allTasks = try await client.fetchTasks(userId: userId)
            lastRefreshed = Date()
            errorMessage = nil
            publishSnapshot()
        } catch let apiError as ReclaimAPIError {
            guard !silent else { return }
            if case .unauthorized = apiError { signOut(); errorMessage = apiError.localizedDescription }
            else { errorMessage = apiError.localizedDescription }
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
    }

    /// Write the glance snapshot to the App Group and refresh the widget.
    private func publishSnapshot() {
        SharedStore.saveSnapshot(glanceTasks.map { $0.snapshot })
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Mutations

    func bulkComplete(ids: [Int]) async {
        await mutate("Completed \(ids.count) task(s).", optimistic: { self.applyArchived(ids: ids) }, reload: false) { try await $0.bulkComplete(ids: ids) }
    }
    func bulkDelete(ids: [Int]) async {
        await mutate("Deleted \(ids.count) task(s).", optimistic: { self.removeTasks(ids: ids) }, reload: false) { try await $0.bulkDelete(ids: ids) }
    }
    func bulkReprioritize(ids: [Int], to priority: Priority) async {
        await mutate("Set \(ids.count) to \(priority.short).", optimistic: { self.apply(ids: ids) { $0.priority = priority.rawValue } }) { try await $0.bulkReprioritize(ids: ids, to: priority) }
    }
    func bulkReschedule(ids: [Int], due: Date?) async {
        await mutate(due == nil ? "Cleared due date." : "Rescheduled \(ids.count).", optimistic: { self.apply(ids: ids) { $0.due = due } }) { try await $0.bulkReschedule(ids: ids, due: due) }
    }
    func bulkSnooze(ids: [Int], until: Date?) async {
        await mutate(until == nil ? "Cleared snooze." : "Snoozed \(ids.count).", optimistic: { self.apply(ids: ids) { $0.snoozeUntil = until } }) { try await $0.bulkSnooze(ids: ids, until: until) }
    }
    func bulkSetUpNext(ids: [Int], onDeck: Bool) async {
        await mutate(onDeck ? "Moved to Up Next." : "Removed from Up Next.", optimistic: { self.apply(ids: ids) { $0.onDeck = onDeck } }) { try await $0.bulkSetUpNext(ids: ids, onDeck: onDeck) }
    }
    func markComplete(id: Int) async {
        await mutate("Completed task.", optimistic: { self.applyArchived(ids: [id]) }, reload: false) { try await $0.markComplete(id: id) }
    }
    func markIncomplete(id: Int) async {
        await mutate("Reopened task.", optimistic: { self.apply(ids: [id]) { $0.status = TaskStatus.scheduled.rawValue; $0.finished = nil } }) { try await $0.markIncomplete(id: id) }
    }
    func createTask(title: String, priority: Priority, durationHours: Double, due: Date?) async {
        await mutate("Added task.") { _ = try await $0.createTask(title: title, priority: priority, durationHours: durationHours, due: due) }
    }
    func updateTask(id: Int, patch: [String: Any]) async {
        guard !patch.isEmpty else { return }
        await mutate("Saved changes.") { try await $0.updateTask(id: id, patch: patch) }
    }

    private func apply(ids: [Int], _ transform: (inout ReclaimTask) -> Void) {
        let set = Set(ids)
        for i in allTasks.indices where set.contains(allTasks[i].id) { transform(&allTasks[i]) }
    }
    private func applyArchived(ids: [Int]) {
        apply(ids: ids) { $0.status = TaskStatus.archived.rawValue; $0.onDeck = false; $0.finished = Date() }
    }
    private func removeTasks(ids: [Int]) {
        let set = Set(ids)
        allTasks.removeAll { set.contains($0.id) }
    }

    private func mutate(_ successMessage: String, optimistic: (() -> Void)? = nil, reload: Bool = true, _ op: (ReclaimAPIClient) async throws -> Void) async {
        guard let client else { errorMessage = ReclaimAPIError.noToken.localizedDescription; return }
        isBusy = true
        defer { isBusy = false }
        let snapshot = allTasks
        optimistic?()
        do {
            try await op(client)
            statusMessage = successMessage
            errorMessage = nil
            if reload { await loadTasks() } else { publishSnapshot() }
        } catch let apiError as ReclaimAPIError {
            allTasks = snapshot
            errorMessage = apiError.localizedDescription
        } catch {
            allTasks = snapshot
            errorMessage = error.localizedDescription
        }
    }
}
