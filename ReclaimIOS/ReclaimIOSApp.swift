import SwiftUI

@main
struct ReclaimIOSApp: App {
    @State private var viewModel = TaskListViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(vm: viewModel)
        }
    }
}
