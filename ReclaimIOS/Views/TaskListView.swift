import SwiftUI
import ReclaimKit

struct TaskListView: View {
    @Bindable var vm: TaskListViewModel
    @State private var selection = Set<Int>()
    @State private var editMode: EditMode = .inactive
    @State private var showCreate = false
    @State private var showSettings = false
    @State private var pendingDeleteIDs: [Int]?
    @AppStorage("wrapTaskTitles") private var wrapTitles = false

    private var selectedIDs: [Int] { Array(selection) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $vm.filter) {
                    ForEach(TaskFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.vertical, 6)

                list
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("Reclaim")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.searchText, prompt: "Search tasks")
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) {
                if editMode.isEditing && !selection.isEmpty {
                    BulkBar(vm: vm, selectedIDs: selectedIDs,
                            onDelete: { pendingDeleteIDs = selectedIDs },
                            onDone: { selection.removeAll(); editMode = .inactive })
                }
            }
            .sheet(isPresented: $showCreate) { TaskCreateView(vm: vm) }
            .sheet(isPresented: $showSettings) { SettingsView(vm: vm) }
            .confirmationDialog(
                "Delete \(pendingDeleteIDs?.count ?? 0) task\((pendingDeleteIDs?.count ?? 0) == 1 ? "" : "s")?",
                isPresented: Binding(get: { pendingDeleteIDs != nil }, set: { if !$0 { pendingDeleteIDs = nil } }),
                titleVisibility: .visible
            ) {
                if let ids = pendingDeleteIDs {
                    Button("Delete \(ids.count)", role: .destructive) {
                        Task { await vm.bulkDelete(ids: ids) }
                        selection.subtract(ids); pendingDeleteIDs = nil
                    }
                }
                Button("Cancel", role: .cancel) { pendingDeleteIDs = nil }
            } message: { Text("This permanently deletes from Reclaim and cannot be undone.") }
            .onChange(of: editMode) { _, m in if !m.isEditing { selection.removeAll() } }
            .overlay { if vm.filteredTasks.isEmpty { emptyState } }
            .overlay { if vm.isBusy { busyHUD } }
        }
    }

    /// Centered spinner shown while a mutating API call is in flight, so button
    /// taps register visibly instead of appearing to hang.
    private var busyHUD: some View {
        ZStack {
            Color.black.opacity(0.06).ignoresSafeArea()
            ProgressView()
                .controlSize(.large)
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .shadow(radius: 10)
        }
        .transition(.opacity)
        .allowsHitTesting(true)   // swallow taps so an action can't be double-fired
    }

    private var list: some View {
        List(selection: $selection) {
            if !vm.upNextTasks.isEmpty {
                Section("⚡︎ Up Next") { ForEach(vm.upNextTasks) { row($0) } }
                Section("Tasks") { ForEach(vm.otherTasks) { row($0) } }
            } else {
                ForEach(vm.otherTasks) { row($0) }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: ReclaimTask.self) { TaskEditView(vm: vm, task: $0) }
        .refreshable { await vm.loadTasks() }
    }

    private func row(_ task: ReclaimTask) -> some View {
        NavigationLink(value: task) { TaskRow(task: task) }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if task.isFinished {
                    Button { Task { await vm.markIncomplete(id: task.id) } } label: { Label("Reopen", systemImage: "arrow.uturn.backward") }.tint(.blue)
                } else {
                    Button { Task { await vm.markComplete(id: task.id) } } label: { Label("Complete", systemImage: "checkmark") }.tint(.green)
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { pendingDeleteIDs = [task.id] } label: { Label("Delete", systemImage: "trash") }
                Button { Task { await vm.bulkSetUpNext(ids: [task.id], onDeck: !(task.onDeck ?? false)) } } label: {
                    Label("Up Next", systemImage: task.onDeck == true ? "bolt.slash" : "bolt")
                }.tint(.yellow)
            }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(vm.isLoading ? "Loading…" : "No tasks", systemImage: vm.filter.systemImage)
        } description: {
            Text(vm.isLoading ? "Fetching your Reclaim tasks." : "Nothing matches this filter.")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(editMode.isEditing ? "Done" : "Select") {
                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showCreate = true } label: { Image(systemName: "plus") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { Task { await vm.loadTasks() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                Divider()
                Picker("Sort By", selection: $vm.sortOption) {
                    ForEach(SortOption.allCases) { Label($0.rawValue, systemImage: $0.systemImage).tag($0) }
                }
                Button {
                    vm.sortAscending.toggle()
                } label: {
                    Label(vm.sortAscending ? "Ascending" : "Descending",
                          systemImage: vm.sortAscending ? "arrow.up" : "arrow.down")
                }
                Toggle(isOn: $wrapTitles) { Label("Wrap long titles", systemImage: "text.alignleft") }
                Divider()
                if let user = vm.user { Text(user.displayName) }
                Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            } label: { Image(systemName: "ellipsis.circle") }
        }
    }
}

/// One task row.
struct TaskRow: View {
    let task: ReclaimTask
    @AppStorage("wrapTaskTitles") private var wrapTitles = false
    var body: some View {
        HStack(alignment: wrapTitles ? .top : .center, spacing: 10) {
            if let p = task.priorityEnum {
                Text(p.short).font(.caption2.bold())
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(p.color.opacity(0.18), in: Capsule())
                    .foregroundStyle(p.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if task.onDeck == true { Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.yellow) }
                    Text(task.displayTitle).lineLimit(wrapTitles ? nil : 1)
                        .strikethrough(task.isFinished, color: .secondary)
                        .foregroundStyle(task.isFinished ? .secondary : .primary)
                }
                HStack(spacing: 8) {
                    if task.due != nil {
                        Label(Fmt.day(task.due), systemImage: "calendar")
                            .foregroundStyle(task.isOverdue ? .red : .secondary)
                    }
                    if let d = task.durationHours, d > 0 {
                        Label(Fmt.duration(d), systemImage: "clock").foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
