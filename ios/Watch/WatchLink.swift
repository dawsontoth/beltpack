import Foundation
import WatchConnectivity

/// The wrist's half of the link.
///
/// Holds no opinion about whether it is transmitting — it asks the phone and
/// renders whatever comes back. `sendMessage` only works while the phone app
/// is reachable, and that failure is surfaced rather than swallowed: a talk
/// button that silently does nothing is worse than one that says it cannot.
@MainActor
final class WatchLink: NSObject, ObservableObject {
    @Published private(set) var snapshot: CommsSnapshot = .unknown
    @Published private(set) var isReachable = false
    @Published private(set) var lastError: String?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ action: CommsLink.Action) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            lastError = "Watch not paired"
            return
        }
        guard session.isReachable else {
            // Reachability means the phone app is running and in the
            // foreground-ish state WatchConnectivity requires. Nothing useful
            // happens if we pretend otherwise.
            lastError = "Open Beltpack on your phone"
            return
        }

        lastError = nil
        session.sendMessage(
            [CommsLink.actionKey: action.rawValue],
            replyHandler: { [weak self] reply in
                Task { @MainActor in
                    if let snapshot = CommsSnapshot.decoded(from: reply) {
                        self?.snapshot = snapshot
                    }
                }
            },
            errorHandler: { [weak self] error in
                Task { @MainActor in self?.lastError = error.localizedDescription }
            },
        )
    }

    func refresh() {
        isReachable = WCSession.isSupported() && WCSession.default.isReachable
        if isReachable { send(.status) }
    }

    private func apply(_ snapshot: CommsSnapshot?) {
        guard let snapshot else { return }
        self.snapshot = snapshot
        lastError = nil
    }
}

extension WatchLink: WCSessionDelegate {
    // WCSession and its dictionaries are not Sendable, so everything is
    // reduced to plain values before crossing to the main actor.
    nonisolated func session(_ session: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            if reachable { self.send(.status) }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            if reachable { self.send(.status) }
        }
    }

    nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        let snapshot = CommsSnapshot.decoded(from: message)
        Task { @MainActor in self.apply(snapshot) }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext context: [String: Any]) {
        let snapshot = CommsSnapshot.decoded(from: context)
        Task { @MainActor in self.apply(snapshot) }
    }
}
