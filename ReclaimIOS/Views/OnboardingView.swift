import SwiftUI

/// First-run screen to capture the Reclaim API key.
struct OnboardingView: View {
    @Bindable var vm: TaskListViewModel
    @State private var token = ""

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 52)).foregroundStyle(.tint)
            Text("Connect to Reclaim.ai").font(.title.bold())
            Text("Paste your Reclaim API key to get started. Create one at reclaim.ai → Settings → Developer.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)

            SecureField("Reclaim API key", text: $token)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(connect)

            if let error = vm.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }

            Button(action: connect) {
                if vm.isBusy { ProgressView() } else { Text("Connect").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isBusy)

            Text("Your key is stored securely in the iOS Keychain.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(28)
    }

    private func connect() { Task { await vm.saveToken(token) } }
}
