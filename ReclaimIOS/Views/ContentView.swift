import SwiftUI

/// Routes to onboarding when no token is configured, otherwise the task list.
struct ContentView: View {
    @Bindable var vm: TaskListViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if vm.isConfigured {
                TaskListView(vm: vm)
            } else {
                OnboardingView(vm: vm)
            }
        }
        .task {
            if vm.isConfigured && vm.allTasks.isEmpty { await vm.loadTasks() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && vm.isConfigured {
                Task { await vm.loadTasks(silent: true) }
            }
        }
    }
}
