import SwiftUI

struct WatchContentView: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        NavigationStack {
            Group {
                if !model.isConfigured {
                    ContentUnavailableView(
                        "Not Connected",
                        systemImage: "iphone",
                        description: Text("Open Reclaim on your iPhone to sync.")
                    )
                } else if model.tasks.isEmpty {
                    if model.isLoading {
                        ProgressView()
                    } else {
                        ContentUnavailableView("All Clear", systemImage: "checkmark.circle", description: Text("Nothing up next."))
                    }
                } else {
                    List(model.tasks) { task in
                        Button {
                            Task { await model.complete(task.id) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "circle")
                                    .foregroundStyle(task.priorityEnum?.watchColor ?? .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 3) {
                                        if task.onDeck == true {
                                            Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.yellow)
                                        }
                                        Text(task.displayTitle).font(.body).lineLimit(2)
                                    }
                                    if let due = task.due {
                                        Text(due, style: .date).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Up Next")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await model.load() }
                    } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .task { await model.load() }
    }
}

private extension Priority {
    var watchColor: Color {
        switch self {
        case .p1: return .red
        case .p2: return .orange
        case .p3: return .blue
        case .p4: return .secondary
        }
    }
}
