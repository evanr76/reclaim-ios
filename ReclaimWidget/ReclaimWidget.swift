import WidgetKit
import SwiftUI
import ReclaimKit

// MARK: - Timeline

struct Entry: TimelineEntry {
    let date: Date
    let tasks: [SharedStore.TaskSnapshot]
}

struct Provider: TimelineProvider {
    private var sample: [SharedStore.TaskSnapshot] {
        [
            .init(id: 1, title: "Review Q3 metrics", priority: "P1", dueDate: Date(), onDeck: true, overdue: false),
            .init(id: 2, title: "Reply to RTS thread", priority: "P2", dueDate: Date(), onDeck: false, overdue: false),
            .init(id: 3, title: "Draft AI use policy", priority: "P3", dueDate: nil, onDeck: false, overdue: false),
        ]
    }

    func placeholder(in context: Context) -> Entry { Entry(date: Date(), tasks: sample) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let tasks = context.isPreview ? sample : SharedStore.loadSnapshot()
        completion(Entry(date: Date(), tasks: tasks))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: Date(), tasks: SharedStore.loadSnapshot())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Views

private func priorityColor(_ raw: String?) -> Color {
    switch raw {
    case "P1": return .red
    case "P2": return .orange
    case "P3": return .blue
    default: return .secondary
    }
}

private let dayFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "MMM d"; return f
}()

struct ReclaimWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    private var limit: Int { family == .systemSmall ? 3 : 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill").foregroundStyle(.yellow).font(.caption2)
                Text("Up Next").font(.caption.bold())
                Spacer()
            }
            if entry.tasks.isEmpty {
                Spacer()
                Text("Nothing up next 🎉").font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.tasks.prefix(limit)) { task in
                    HStack(spacing: 6) {
                        Circle().fill(priorityColor(task.priority)).frame(width: 6, height: 6)
                        Text(task.title).font(.caption2).lineLimit(1)
                        Spacer(minLength: 0)
                        if family != .systemSmall, let due = task.dueDate {
                            Text(dayFormatter.string(from: due))
                                .font(.caption2)
                                .foregroundStyle(task.overdue ? .red : .secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Widget

struct ReclaimWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReclaimWidget", provider: Provider()) { entry in
            ReclaimWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Up Next")
        .description("Your Up Next and top-priority Reclaim tasks.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ReclaimWidgetBundle: WidgetBundle {
    var body: some Widget { ReclaimWidget() }
}
