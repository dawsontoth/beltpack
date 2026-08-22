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
    @Published private(set) var consoleIsLive = false
    @Published private(set) var isTalking = false
    @Published private(set) var micDenied = false

    private var micPublication: LocalTrackPublication?

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
            try configureAudioSession(forTalking: false)
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
            if Settings.talkMode == .open {
                await startTalking()
            }
            // The bridge is normally already in the room when a beltpack
            // joins, so no participantDidConnect fires for it. Seed from
            // current state or the UI claims nothing is there.
            refreshTalkers(room)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func disconnect() async {
        await stopTalking()
        await room.disconnect()
        state = .idle
        talkers = []
        consoleIsLive = false
    }

    /// Listen-only stays on `.playback`, which keeps the earbuds in A2DP/AAC
    /// at full bandwidth. Once a mic is involved the category has to become
    /// `.playAndRecord`, and the options then decide whether the earbuds keep
    /// their quality — see `MicMode`.
    private func configureAudioSession(forTalking: Bool) throws {
        let session = AVAudioSession.sharedInstance()

        if forTalking {
            let mode = Settings.micMode
            try session.setCategory(.playAndRecord, mode: mode.sessionMode, options: mode.sessionOptions)
            try session.setActive(true)
            if mode == .phoneMic {
                // The decisive step. Without pinning input to the built-in mic
                // iOS will happily route input to the earbuds anyway, drag the
                // link into HFP, and undo the whole point of this mode.
                if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                    try? session.setPreferredInput(builtIn)
                }
            }
        } else {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        }

        if #available(iOS 14.5, *) {
            try? session.setPrefersNoInterruptionsFromSystemAlerts(true)
        }
    }

    // MARK: - Talking

    func startTalking() async {
        guard case .listening = state, micPublication == nil else { return }

        guard await AVAudioApplication.requestRecordPermission() else {
            micDenied = true
            return
        }
        micDenied = false

        do {
            try configureAudioSession(forTalking: true)

            // A voice in a loud sanctuary, unlike the console feed: leave
            // WebRTC's echo cancellation and noise suppression switched on.
            let track = LocalAudioTrack.createTrack(
                name: "beltpack",
                options: AudioCaptureOptions(
                    echoCancellation: true,
                    autoGainControl: true,
                    noiseSuppression: true,
                ),
            )
            micPublication = try await room.localParticipant.publish(audioTrack: track)
            isTalking = true
        } catch {
            state = .failed(error.localizedDescription)
            try? configureAudioSession(forTalking: false)
        }
    }

    func stopTalking() async {
        guard let publication = micPublication else { return }
        micPublication = nil
        isTalking = false
        try? await room.localParticipant.unpublish(publication: publication)
        // Back to .playback so the earbuds return to full-bandwidth listening.
        try? configureAudioSession(forTalking: false)
    }

    func toggleTalking() async {
        if isTalking { await stopTalking() } else { await startTalking() }
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

    nonisolated func room(_ room: Room, participant _: RemoteParticipant, didSubscribeTrack _: RemoteTrackPublication) {
        Task { @MainActor in self.refreshTalkers(room) }
    }

    nonisolated func room(_ room: Room, participant _: RemoteParticipant, didUnsubscribeTrack _: RemoteTrackPublication) {
        Task { @MainActor in self.refreshTalkers(room) }
    }

    @MainActor
    private func refreshTalkers(_ room: Room) {
        let remotes = Array(room.remoteParticipants.values)
        talkers = remotes.compactMap(\.identity?.stringValue).sorted()
        // Detected by an audible track rather than by matching the bridge's
        // identity, so renaming the bridge cannot silently break this.
        consoleIsLive = remotes.contains { participant in
            participant.audioTracks.contains { $0.isSubscribed }
        }
    }
}
