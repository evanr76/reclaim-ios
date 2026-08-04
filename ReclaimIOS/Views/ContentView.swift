import SwiftUI
import ReclaimKit

/// Routes to onboarding when no token is configured, otherwise the task list.
struct ContentView: View {
    @Bindable var vm: TaskListViewModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        Group {
            if vm.isConfigured {
                TaskListView(vm: vm)
            } else {
                OnboardingView(vm: vm)
            }
        }
        .preferredColorScheme(AppAppearance(rawValue: appearanceRaw)?.colorScheme)
        .task {
            LiveActivityManager.endStaleActivities()
            PhoneConnectivity.shared.start()
            NotificationScheduler.configure()
            await NotificationScheduler.requestAuthorization()
            if vm.isConfigured && vm.allTasks.isEmpty { await vm.loadTasks() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Clear a finished block's activity immediately on foreground,
                // independent of the (possibly slow/failing) network refresh.
                LiveActivityManager.endStaleActivities()
                if vm.isConfigured {
                    Task { await vm.loadTasks(silent: true) }
                }
            }
        }
    }
}
