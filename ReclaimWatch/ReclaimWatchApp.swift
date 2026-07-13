import SwiftUI

@main
struct ReclaimWatchApp: App {
    @StateObject private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchContentView(model: model)
        }
    }
}
