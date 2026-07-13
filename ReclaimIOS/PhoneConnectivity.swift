import Foundation
import WatchConnectivity
import ReclaimKit

/// iPhone side of the watch bridge: pushes the API token to the paired watch so
/// the watch app can fetch tasks on its own.
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Send the current token (or empty to sign the watch out) to the watch.
    func syncToken() {
        guard WCSession.default.activationState == .activated else { return }
        let token = KeychainStore.readToken() ?? ""
        try? WCSession.default.updateApplicationContext(["reclaimToken": token])
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated { syncToken() }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
