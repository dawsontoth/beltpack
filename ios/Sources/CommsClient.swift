import AVFAudio
import Combine
import Foundation
import LiveKit

/// Joins the comms room and keeps listening while the phone is in a pocket.
///
/// Phase 1 subscribes only. Push-to-talk arrives in phase 2; see README.md for
/// why publishing a mic costs you AirPods audio quality and how to avoid it.
@MainActor
final class CommsClient: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case listening
        case reconnecting
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var talkers: [String] = []

    private let room = Room()
    private var listenerTask: Task<Void, Never>?

    init() {
        room.add(delegate: self)
    }

    func connect() async {
        guard Settings.isConfigured else {
            state = .failed("Set the server, name, and passcode first.")
            return
        }

        state = .connecting

        do {
            try configureAudioSession()
            let credentials = try await TokenService.fetch(
                serverURL: Settings.serverURL,
                identity: Settings.identity,
                passcode: Settings.passcode,
            )
            try await room.connect(
                url: credentials.url,
                token: credentials.token,
                roomOptions: RoomOptions(adaptiveStream: false, dynacast: false),
            )
            state = .listening
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func disconnect() async {
        await room.disconnect()
        state = .idle
        talkers = []
    }

    /// `.playback` keeps AirPods in A2DP/AAC at full bandwidth. Do not switch
    /// this to `.playAndRecord` casually — that flips them to hands-free mode
    /// and everything drops to 16 kHz mono in both directions.
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        try session.setActive(true)
        if #available(iOS 14.5, *) {
            try? session.setPrefersNoInterruptionsFromSystemAlerts(true)
        }
    }
}

extension CommsClient: RoomDelegate {
    nonisolated func room(_: Room, didUpdateConnectionState state: ConnectionState, from _: ConnectionState) {
        Task { @MainActor in
            switch state {
            case .connected: self.state = .listening
            case .reconnecting: self.state = .reconnecting
            case .disconnected: if self.state != .idle { self.state = .reconnecting }
            default: break
            }
        }
    }

    nonisolated func room(_ room: Room, participantDidConnect _: RemoteParticipant) {
        Task { @MainActor in self.refreshTalkers(room) }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect _: RemoteParticipant) {
        Task { @MainActor in self.refreshTalkers(room) }
    }

    @MainActor
    private func refreshTalkers(_ room: Room) {
        talkers = room.remoteParticipants.values
            .compactMap(\.identity?.stringValue)
            .sorted()
    }
}
