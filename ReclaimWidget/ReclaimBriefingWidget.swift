import WidgetKit
import SwiftUI
import ReclaimKit

/// Home-screen widget that renders the on-device daily briefing. The model can't
/// run inside the widget's memory budget, so the app generates the text and
/// caches it in the App Group; this widget just displays it.
struct BriefingEntry: TimelineEntry {
    let date: Date
    let briefing: SharedStore.Briefing?
}

struct BriefingProvider: TimelineProvider {
    private var sample: SharedStore.Briefing {
        .init(text: "Two P1 items anchor your day: ship the Q3 deck before the 2 pm review, then clear the RTS thread. The afternoon is lighter — a good window for the AI policy draft.",
              generatedAt: Date())
    }

    func placeholder(in context: Context) -> BriefingEntry {
        BriefingEntry(date: Date(), briefing: sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BriefingEntry) -> Void) {
        let briefing = context.isPreview ? sample : SharedStore.loadBriefing()
        completion(BriefingEntry(date: Date(), briefing: briefing))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BriefingEntry>) -> Void) {
        let entry = BriefingEntry(date: Date(), briefing: SharedStore.loadBriefing())
        let next = Calendar.current.date(byAdding: .hour, value: 3, to: Date()) ?? Date().addingTimeInterval(10800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct BriefingEntryView: View {
    let entry: BriefingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles").foregroundStyle(.yellow).font(.caption2)
                Text("Today").font(.caption.bold())
                Spacer()
            }
            if let briefing = entry.briefing {
                Text(briefing.text)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(7)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("Updated \(briefing.generatedAt, style: .time)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            } else {
                Spacer()
                Text("Open Reclaim to generate today's briefing.")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

struct ReclaimBriefingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReclaimBriefingWidget", provider: BriefingProvider()) { entry in
            BriefingEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daily Briefing")
        .description("A short, on-device summary of your day.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
