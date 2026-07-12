import SwiftUI

/// A button that runs an async action, replacing its label with a spinner and
/// disabling (dimming) itself while the action is in flight — so back-end calls
/// give immediate feedback instead of feeling momentarily hung. Works anywhere,
/// including inside sheets and pushed detail views where a list-level overlay
/// isn't visible.
struct AsyncButton<Label: View>: View {
    var role: ButtonRole? = nil
    let action: () async -> Void
    @ViewBuilder var label: () -> Label

    @State private var running = false

    var body: some View {
        Button(role: role) {
            guard !running else { return }
            running = true
            Task {
                await action()
                running = false
            }
        } label: {
            label()
                .opacity(running ? 0 : 1)
                .overlay { if running { ProgressView().controlSize(.small) } }
        }
        .disabled(running)
    }
}
