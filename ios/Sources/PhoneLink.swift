import Foundation
import WatchConnectivity

/// The phone's half of the watch link.
///
/// Receives intent from the wrist and hands it to `CommsClient`, then pushes
/// the resulting state back. Nothing here decides anything — it is a wire.
@MainActor
final class PhoneLink: NSObject, ObservableObject {
    private weak var comms: CommsClient?
    private var lastSent: CommsSnapshot?

    func attach(to comms: CommsClient) {
        self.comms = comms
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Called whenever the phone's state changes. Coalesced: sending an
    /// identical snapshot would just burn radio for no visible difference.
    func publish(_ snapshot: CommsSnapshot) {
        guard WCSession.isSupported(), snapshot != lastSent else { return }
        lastSent = snapshot

        let session = WCSession.default
        guard session.activationState == .activated else { return }

        if session.isReachable {
            // Live path: the watch face is up and wants this now.
            session.sendMessage(snapshot.encoded(), replyHandler: nil, errorHandler: nil)
        }
        // Always leave the latest state behind as well, so a watch that wakes
        // up later opens on the truth rather than on whatever it last saw.
        try? session.updateApplicationContext(snapshot.encoded())
    }

    private func handle(_ action: CommsLink.Action) async {
        guard let comms else { return }
        switch action {
        case .status: break
        case .startTalking: await comms.startTalking()
        case .stopTalking: await comms.stopTalking()
        case .toggleTalking: await comms.toggleTalking()
        }
    }
}

/// Carries WatchConnectivity's non-Sendable reply callback across one hop.
private struct ReplyBox: @unchecked Sendable {
    let reply: ([String: Any]) -> Void
}

extension PhoneLink: WCSessionDelegate {
    nonisolated func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {}
    nonisolated func sessionDidBecomeInactive(_: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let action = (message[CommsLink.actionKey] as? String).flatMap(CommsLink.Action.init(rawValue:))
        // WCSessionDelegate hands over a non-Sendable callback, and the
        // protocol signature cannot be changed. It is only ever called once,
        // from the hop below, so boxing it is safe rather than merely quiet.
        let box = ReplyBox(reply: replyHandler)
        Task { @MainActor in
            if let action { await self.handle(action) }
            // Reply with the state that actually resulted, so the wrist shows
            // what happened rather than what was asked for.
            let snapshot = self.comms?.snapshot ?? .unknown
            box.reply(snapshot.encoded())
        }
    }

    nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        let action = (message[CommsLink.actionKey] as? String).flatMap(CommsLink.Action.init(rawValue:))
        Task { @MainActor in
            guard let action else { return }
            await self.handle(action)
        }
    }
}
