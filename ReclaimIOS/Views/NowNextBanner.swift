import SwiftUI
import ReclaimKit

/// "Now & Next" scheduled-block banner, fed by Reclaim's moment endpoints.
struct NowNextBanner: View {
    let current: MomentEvent?
    let next: MomentEvent?

    private var showCurrent: Bool { current?.isActive() == true }

    var body: some View {
        if current == nil && next == nil {
            EmptyView()
        } else {
            VStack(spacing: 8) {
                if let c = current, c.isActive() {
                    row(label: "NOW", event: c, accent: .green, showEnd: true)
                }
                if let n = next {
                    if showCurrent { Divider() }
                    row(label: "NEXT", event: n, accent: .blue, showEnd: false)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func row(label: String, event: MomentEvent, accent: Color, showEnd: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(label).font(.caption2.bold()).foregroundStyle(accent)
                if let p = event.priorityEnum {
                    Text(p.short).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayTitle).font(.subheadline.weight(.medium)).lineLimit(1)
                Group {
                    if showEnd, let end = event.eventEnd {
                        Text("ends ") + Text(end, style: .relative)
                    } else if let start = event.eventStart {
                        Text(start, style: .time) + Text(" · in ") + Text(start, style: .relative)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let urlString = event.onlineMeetingUrl, let url = URL(string: urlString) {
                Link(destination: url) {
                    Image(systemName: "video.fill").foregroundStyle(accent)
                }
            }
        }
    }
}
