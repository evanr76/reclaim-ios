import SwiftUI
import ReclaimKit

/// Bottom bar shown while tasks are selected in edit mode.
struct BulkBar: View {
    @Bindable var vm: TaskListViewModel
    let selectedIDs: [Int]
    var onDelete: () -> Void
    var onDone: () -> Void

    @State private var showDatePicker = false
    @State private var pickedDate = Date()

    var body: some View {
        HStack(spacing: 16) {
            Text("\(selectedIDs.count) selected").font(.footnote).foregroundStyle(.secondary)

            Spacer()

            Button { run { await vm.bulkComplete(ids: selectedIDs) } } label: {
                Image(systemName: "checkmark.circle")
            }
            .help("Complete")

            Menu {
                Menu("Set Priority") {
                    ForEach(Priority.allCases) { p in
                        Button(p.label) { run { await vm.bulkReprioritize(ids: selectedIDs, to: p) } }
                    }
                }
                Button("Move to Up Next", systemImage: "bolt") { run { await vm.bulkSetUpNext(ids: selectedIDs, onDeck: true) } }
                Button("Remove from Up Next", systemImage: "bolt.slash") { run { await vm.bulkSetUpNext(ids: selectedIDs, onDeck: false) } }
                Menu("Snooze") {
                    Button("Tomorrow") { run { await vm.bulkSnooze(ids: selectedIDs, until: Self.tomorrow()) } }
                    Button("Next week") { run { await vm.bulkSnooze(ids: selectedIDs, until: Self.nextMonday()) } }
                    Button("Clear snooze") { run { await vm.bulkSnooze(ids: selectedIDs, until: nil) } }
                }
                Menu("Reschedule") {
                    Button("Tomorrow") { run { await vm.bulkReschedule(ids: selectedIDs, due: Self.tomorrow()) } }
                    Button("Next week") { run { await vm.bulkReschedule(ids: selectedIDs, due: Self.nextMonday()) } }
                    Button("Pick date…") { showDatePicker = true }
                    Button("Clear due date") { run { await vm.bulkReschedule(ids: selectedIDs, due: nil) } }
                }
            } label: { Image(systemName: "ellipsis.circle") }

            Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }

            Button("Done") { onDone() }.font(.body.weight(.semibold))
        }
        .padding(.horizontal).padding(.vertical, 10)
        .background(.bar)
        .disabled(vm.isBusy)
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                DatePicker("Due date", selection: $pickedDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Reschedule")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showDatePicker = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Apply") {
                                run { await vm.bulkReschedule(ids: selectedIDs, due: pickedDate) }
                                showDatePicker = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func run(_ op: @escaping () async -> Void) {
        Task { await op(); onDone() }
    }

    private static func tomorrow() -> Date {
        let cal = Calendar.current
        let t = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: t) ?? t
    }
    private static func nextMonday() -> Date {
        let cal = Calendar.current
        var d = Date()
        for _ in 0..<8 { d = cal.date(byAdding: .day, value: 1, to: d) ?? d; if cal.component(.weekday, from: d) == 2 { break } }
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
    }
}
