import SwiftUI
import ReclaimKit

enum RefreshInterval: Int, CaseIterable, Identifiable {
    case off = 0, m15 = 15, m30 = 30, hourly = 60, h2 = 120
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .off: return "Off"
        case .m15: return "Every 15 minutes"
        case .m30: return "Every 30 minutes"
        case .hourly: return "Hourly"
        case .h2: return "Every 2 hours"
        }
    }
}

struct SettingsView: View {
    @Bindable var vm: TaskListViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newToken = ""
    @AppStorage("refreshIntervalMinutes") private var refreshIntervalMinutes = 60
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage("notifyAtRisk") private var notifyAtRisk = true
    @AppStorage("notifyBlockStarting") private var notifyBlockStarting = true
    @AppStorage("notifyUpNext") private var notifyUpNext = true
    @AppStorage("notifyDigest") private var notifyDigest = true
    @AppStorage("digestHour") private var digestHour = 8

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if let user = vm.user {
                        LabeledContent("Signed in as", value: user.displayName)
                        if let email = user.email { LabeledContent("Email", value: email) }
                    } else {
                        Text("Not connected.").foregroundStyle(.secondary)
                    }
                }

                Section("General") {
                    Picker("Appearance", selection: $appearanceRaw) {
                        ForEach(AppAppearance.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("Refresh", selection: $refreshIntervalMinutes) {
                        ForEach(RefreshInterval.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .onChange(of: refreshIntervalMinutes) { _, m in vm.configureAutoRefresh(intervalMinutes: m) }
                    Text("Auto-refresh runs only while the app is open and online.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Notifications") {
                    Toggle("At-risk alerts", isOn: $notifyAtRisk)
                    Toggle("Block starting soon", isOn: $notifyBlockStarting)
                    Toggle("Up Next changes", isOn: $notifyUpNext)
                    Toggle("Morning digest", isOn: $notifyDigest)
                    if notifyDigest {
                        Picker("Digest time", selection: $digestHour) {
                            ForEach(5..<12) { Text("\($0):00").tag($0) }
                        }
                    }
                }

                Section("API Key") {
                    SecureField("Replace API key", text: $newToken)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Update Key") {
                        Task { await vm.saveToken(newToken); newToken = "" }
                    }
                    .disabled(newToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isBusy)
                    Button("Sign Out", role: .destructive) { vm.signOut(); dismiss() }
                        .disabled(!vm.isConfigured)
                    Text("Stored in the iOS Keychain; sent only to api.app.reclaim.ai.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
