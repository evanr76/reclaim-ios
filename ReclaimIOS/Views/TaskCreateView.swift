import SwiftUI
import ReclaimKit

/// Sheet to create a new task.
struct TaskCreateView: View {
    @Bindable var vm: TaskListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var priority: Priority = .p3
    @State private var hasDue = false
    @State private var due = Date()
    @State private var durationHours: Double = 1

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Title", text: $title, axis: .vertical) }
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
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    AsyncButton(action: {
                        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        await vm.createTask(title: t, priority: priority, durationHours: durationHours, due: hasDue ? due : nil)
                        dismiss()
                    }) { Text("Add") }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
