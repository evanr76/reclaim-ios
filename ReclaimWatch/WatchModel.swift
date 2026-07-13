import Foundation
import WatchConnectivity

/// Watch-side state: receives the API token from the paired iPhone via
/// WatchConnectivity, then fetches Up Next tasks directly from the API.
@MainActor
final class WatchModel: NSObject, ObservableObject {
    @Published var tasks: [ReclaimTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isConfigured = false

    override init() {
        super.init()
        isConfigured = resolveToken() != nil
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Keychain token, with a simulator-only env fallback for testing.
    private nonisolated func resolveToken() -> String? {
        if let t = KeychainStore.readToken() { return t }
        #if DEBUG && targetEnvironment(simulator)
        if let e = ProcessInfo.processInfo.environment["RECLAIM_TOKEN"], !e.isEmpty { return e }
        #endif
        return nil
    }

    func load() async {
        guard let token = resolveToken() else { isConfigured = false; return }
        isConfigured = true
        isLoading = true
        defer { isLoading = false }
        let client = ReclaimAPIClient(token: token)
        do {
            let me = try await client.currentUser()
            let all = try await client.fetchTasks(userId: me.id)
            let unfinished = all.filter { !$0.isFinished }
            let upNext = unfinished.filter { $0.onDeck == true }
            let others = unfinished
                .filter { !($0.onDeck ?? false) }
                .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            tasks = Array((upNext + others).prefix(12))
            errorMessage = nil
        } catch {
            errorMessage = (error as? ReclaimAPIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    func complete(_ id: Int) async {
        guard let token = resolveToken() else { return }
        tasks.removeAll { $0.id == id }   // optimistic
        try? await ReclaimAPIClient(token: token).markComplete(id: id)
        await load()
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        applyToken(from: context)
    }

    private nonisolated func applyToken(from context: [String: Any]) {
        guard let token = context["reclaimToken"] as? String else { return }
        if token.isEmpty {
            KeychainStore.deleteToken()
        } else {
            KeychainStore.saveToken(token)
        }
        Task { @MainActor in
            self.isConfigured = KeychainStore.hasToken
            await self.load()
        }
    }
}
