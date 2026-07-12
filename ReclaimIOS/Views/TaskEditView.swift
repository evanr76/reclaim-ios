import SwiftUI
import ReclaimKit

/// Pushed detail screen to edit a single task.
struct TaskEditView: View {
    @Bindable var vm: TaskListViewModel
    let task: ReclaimTask
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var notes: String
    @State private var priority: Priority
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var durationHours: Double

    init(vm: TaskListViewModel, task: ReclaimTask) {
        self.vm = vm
        self.task = task
        _title = State(initialValue: task.title ?? "")
        _notes = State(initialValue: task.notes ?? "")
        _priority = State(initialValue: task.priorityEnum ?? .p3)
        _hasDue = State(initialValue: task.due != nil)
        _due = State(initialValue: task.due ?? Date())
        _durationHours = State(initialValue: task.durationHours ?? 1)
    }

    var body: some View {
        Form {
            Section { TextField("Title", text: $title, axis: .vertical) }
            Section("Notes") { TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...6) }
            Section {
                Picker("Priority", selection: $priority) {
                    ForEach(Priority.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Due date", isOn: $hasDue)
                if hasDue { DatePicker("Due", selection: $due, displayedComponents: [.date, .hourAndMinute]) }
                Stepper(value: $durationHours, in: 0.25...40, step: 0.25) {
                    HStack { Text("Duration"); Spacer(); Text(Fmt.duration(durationHours)).foregroundStyle(.secondary) }
                }
            }
            Section {
                if task.isFinished {
                    AsyncButton(action: { await vm.markIncomplete(id: task.id); dismiss() }) { Text("Reopen") }
                } else {
                    if task.statusEnum == .inProgress {
                        AsyncButton(action: { await vm.stopTask(id: task.id); dismiss() }) {
                            Label("Stop Working", systemImage: "stop.circle")
                        }
                    } else {
                        AsyncButton(action: { await vm.startTask(id: task.id); dismiss() }) {
                            Label("Start Working", systemImage: "play.circle")
                        }
                    }
                    AsyncButton(action: { await vm.markComplete(id: task.id); dismiss() }) { Text("Mark Complete") }
                }
            }
        }
        .navigationTitle("Edit Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                AsyncButton(action: { await performSave() }) { Text("Save") }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func performSave() async {
        var patch: [String: Any] = [
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
            "notes": notes,
            "priority": priority.rawValue,
            "timeChunksRequired": Int((durationHours * 4).rounded()),
        ]
        patch["due"] = hasDue ? ReclaimAPIClient.isoString(due) : NSNull()
        await vm.updateTask(id: task.id, patch: patch)
        dismiss()
    }
}
