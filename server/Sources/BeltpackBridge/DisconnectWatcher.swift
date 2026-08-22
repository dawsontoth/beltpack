import BeltpackKit
import Foundation
import LiveKit

/// Notices when the room drops so the bridge can rebuild the connection.
///
/// Without this the process stays alive, connected to nothing, publishing
/// nothing, and silent about it — which looks healthy from the outside while
/// comms is dead.
actor DisconnectWatcher {
    private(set) var didDisconnect = false

    func reset() { didDisconnect = false }
    private func markDisconnected() { didDisconnect = true }

    nonisolated func noteDisconnected() {
        Task { await self.markDisconnected() }
    }
}

extension DisconnectWatcher: RoomDelegate {
    nonisolated func room(_: Room, didDisconnectWithError _: LiveKitError?) {
        noteDisconnected()
    }

    nonisolated func room(_: Room, didUpdateConnectionState state: ConnectionState, from _: ConnectionState) {
        if state == .disconnected { noteDisconnected() }
    }
}
