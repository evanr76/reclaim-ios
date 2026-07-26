import Foundation
import WidgetKit
import ReclaimKit

/// Generates the on-device daily briefing from the view model's current data and
/// caches it in the shared store for the widget to render.
@available(iOS 26, *)
extension TaskListViewModel {

    /// Regenerate the briefing unless a fresh one already exists (same day and
    /// under a few hours old) — the model call isn't free, so we don't run it on
    /// every refresh.
    func refreshBriefingIfStale(now: Date = Date()) async {
        guard ReclaimIntelligence.isAvailable else { return }

        if let existing = SharedStore.loadBriefing(),
           Calendar.current.isDate(existing.generatedAt, inSameDayAs: now),
           now.timeIntervalSince(existing.generatedAt) < 3 * 3600 {
            return
        }

        let lines = Self.briefingLines(from: allTasks)
        let nowLine = currentEvent.map(Self.eventLine)
        let nextLine = nextEvent.map(Self.eventLine)

        do {
            let text = try await BriefingGenerator.generate(taskLines: lines, nowLine: nowLine, nextLine: nextLine)
            SharedStore.saveBriefing(.init(text: text, generatedAt: now))
            WidgetCenter.shared.reloadTimelines(ofKind: "ReclaimBriefingWidget")
        } catch {
            // Non-fatal: the briefing is a nicety; leave any prior one in place.
        }
    }

    static func briefingLines(from tasks: [ReclaimTask], limit: Int = 8) -> [String] {
        let active = tasks.filter { !$0.isFinished }
        let sorted = active.sorted { ($0.sortPriorityRank, $0.sortDue) < ($1.sortPriorityRank, $1.sortDue) }
        return sorted.prefix(limit).map { task in
            var parts: [String] = []
            if let short = task.priorityEnum?.short { parts.append(short) }
            parts.append(task.displayTitle)
            if let hours = task.durationHours { parts.append(Fmt.duration(hours)) }
            if let due = task.due { parts.append("due " + Self.shortDue.string(from: due)) }
            return parts.joined(separator: " · ")
        }
    }

    static func eventLine(_ event: MomentEvent) -> String {
        var line = event.displayTitle
        if let start = event.eventStart {
            line += " at " + Self.shortTime.string(from: start)
        }
        return line
    }

    private static let shortDue: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mma"
        return f
    }()

    private static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
}
