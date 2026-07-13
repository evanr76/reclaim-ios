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
    @State private var category: EventCategory
    @State private var color: EventColor
    @State private var timeSchemeId: String?
    @State private var split: Bool
    @State private var minChunkHours: Double
    @State private var maxChunkHours: Double

    init(vm: TaskListViewModel, task: ReclaimTask) {
        self.vm = vm
        self.task = task
        _title = State(initialValue: task.title ?? "")
        _notes = State(initialValue: task.notes ?? "")
        _priority = State(initialValue: task.priorityEnum ?? .p3)
        _hasDue = State(initialValue: task.due != nil)
        _due = State(initialValue: task.due ?? Date())
        _durationHours = State(initialValue: task.durationHours ?? 1)
        _category = State(initialValue: task.categoryEnum ?? .work)
        _color = State(initialValue: task.colorEnum ?? .none)
        _timeSchemeId = State(initialValue: task.timeSchemeId)
        let chunks = task.timeChunksRequired ?? 4
        let minC = task.minChunkSize ?? chunks
        _split = State(initialValue: minC < chunks)
        _minChunkHours = State(initialValue: Double(task.minChunkSize ?? 2) / 4.0)
        _maxChunkHours = State(initialValue: Double(task.maxChunkSize ?? 8) / 4.0)
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
            Section("Scheduling") {
                Picker("Hours", selection: $timeSchemeId) {
                    Text("Default").tag(String?.none)
                    ForEach(vm.timeSchemes) { Text($0.displayTitle).tag(String?.some($0.id)) }
                }
                Picker("Category", selection: $category) {
                    ForEach(EventCategory.allCases) { Text($0.label).tag($0) }
                }
                Picker("Color", selection: $color) {
                    ForEach(EventColor.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Split into chunks", isOn: $split)
                if split {
                    Stepper(value: $minChunkHours, in: 0.25...8, step: 0.25) {
                        HStack { Text("Min chunk"); Spacer(); Text(Fmt.duration(minChunkHours)).foregroundStyle(.secondary) }
                    }
                    Stepper(value: $maxChunkHours, in: 0.5...12, step: 0.25) {
                        HStack { Text("Max chunk"); Spacer(); Text(Fmt.duration(maxChunkHours)).foregroundStyle(.secondary) }
                    }
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
        let chunks = Int((durationHours * 4).rounded())
        var patch: [String: Any] = [
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
            "notes": notes,
            "priority": priority.rawValue,
            "timeChunksRequired": chunks,
            "eventCategory": category.rawValue,
            "eventColor": color.rawValue,
        ]
        patch["due"] = hasDue ? ReclaimAPIClient.isoString(due) : NSNull()
        patch["timeSchemeId"] = timeSchemeId ?? NSNull()
        if split {
            patch["minChunkSize"] = max(1, Int((minChunkHours * 4).rounded()))
            patch["maxChunkSize"] = max(1, Int((maxChunkHours * 4).rounded()))
        } else {
            patch["minChunkSize"] = chunks
            patch["maxChunkSize"] = chunks
        }
        await vm.updateTask(id: task.id, patch: patch)
        dismiss()
    }
}
