import AVFAudio
import Combine
import Foundation
import LiveKit
import OSLog

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

    // Read with Console.app, or:
    //   log stream --device --predicate 'subsystem == "org.beltpack"'
    private let log = Logger(subsystem: "org.beltpack", category: "comms")

    /// Set while the user means to be on comms. A drop is only worth retrying
    /// if nobody tapped Leave — an access-point roam should recover itself.
    private var shouldBeConnected = false
    private var reconnectTask: Task<Void, Never>?

    /// Shared so the meter views can observe it directly without the whole
    /// screen redrawing twenty times a second.
    static let sharedLevels = AudioLevels()
    var levels: AudioLevels { Self.sharedLevels }
    private lazy var micProcessor = GainProcessor(path: .capture, store: Self.sharedLevels.store, gain: Float(Settings.micGain))
    private lazy var listenProcessor = GainProcessor(path: .render, store: Self.sharedLevels.store, gain: 1)

    private var micTrack: LocalAudioTrack?
    private var micPublication: LocalTrackPublication?

    private let room = Room()
    private var listenerTask: Task<Void, Never>?

    init() {
        room.add(delegate: self)
        // Metering on the render path, gain on the capture path. Listening
        // level is set per remote track instead, which is the supported API.
        AudioManager.shared.capturePostProcessingDelegate = micProcessor
        AudioManager.shared.renderPreProcessingDelegate = listenProcessor
    }

    /// How loud you are to everyone else.
    func setMicGain(_ value: Double) {
        Settings.micGain = value
        micProcessor.gain = Float(value)
    }

    /// How loud everyone else is to you. Applied to every subscribed track,
    /// and to any that arrive later.
    func setListenVolume(_ value: Double) {
        Settings.listenVolume = value
        applyListenVolume()
    }

    private func applyListenVolume() {
        let volume = Settings.listenVolume
        for participant in room.remoteParticipants.values {
            for publication in participant.audioTracks {
                (publication.track as? RemoteAudioTrack)?.volume = volume
            }
        }
    }

    func connect() async {
        guard Settings.isConfigured else {
            state = .failed("Set the server, name, and passcode first.")
            return
        }

        shouldBeConnected = true
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

            // Arm the microphone now, not on the first press. Creating the
            // track, switching the audio session, and negotiating the publish
            // all cost time, and the session switch drags Bluetooth from A2DP
            // to HFP — well over a second on real earbuds. Doing it here means
            // a press is only ever an unmute.
            if Settings.talkMode.needsMicrophone {
                await armMicrophone()
            }
            if Settings.talkMode == .open {
                await startTalking()
            }
            // The bridge is normally already in the room when a beltpack
            // joins, so no participantDidConnect fires for it. Seed from
            // current state or the UI claims nothing is there.
            refreshTalkers(room)
            applyListenVolume()
        } catch {
            if shouldBeConnected {
                scheduleReconnect(reason: error.localizedDescription)
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Retries with backoff. Camera operators roam between access points, and
    /// an unassisted roam is the failure most likely to happen in practice.
    private func scheduleReconnect(reason: String) {
        guard shouldBeConnected, reconnectTask == nil else { return }
        state = .reconnecting

        reconnectTask = Task { [weak self] in
            var delay: Double = 1
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, await self.shouldBeConnected else { break }
                await self.connect()
                if case .listening = await self.state { break }
                delay = min(delay * 2, 15)
            }
            await self?.clearReconnectTask()
        }
    }

    private func clearReconnectTask() {
        reconnectTask = nil
    }

    func disconnect() async {
        shouldBeConnected = false
        reconnectTask?.cancel()
        reconnectTask = nil
        await disarmMicrophone()
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

    /// Publishes the microphone already muted, so pressing talk is a local
    /// unmute rather than a track negotiation.
    private func armMicrophone() async {
        guard micPublication == nil else { return }

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
            // Muted before it is published, so nothing escapes in the gap
            // between publishing and the first mute.
            try await track.mute()
            let armStart = Date()
            micPublication = try await room.localParticipant.publish(audioTrack: track)
            micTrack = track
            // The expensive part, paid once at connect rather than per press.
            log.notice("microphone armed in \(Int(Date().timeIntervalSince(armStart) * 1000))ms")
        } catch {
            state = .failed(error.localizedDescription)
            try? configureAudioSession(forTalking: false)
        }
    }

    private func disarmMicrophone() async {
        if let publication = micPublication {
            try? await room.localParticipant.unpublish(publication: publication)
        }
        micPublication = nil
        micTrack = nil
        isTalking = false
    }

    func startTalking() async {
        guard case .listening = state, !isTalking else { return }

        // Arming should have happened at connect; this only covers someone
        // switching out of listen-only mid-service.
        if micTrack == nil { await armMicrophone() }
        guard let track = micTrack else { return }

        do {
            let started = Date()
            try await track.unmute()
            isTalking = true
            log.notice("talk started in \(Int(Date().timeIntervalSince(started) * 1000))ms")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stopTalking() async {
        guard isTalking, let track = micTrack else { return }
        isTalking = false
        try? await track.mute()
    }

    func toggleTalking() async {
        if isTalking { await stopTalking() } else { await startTalking() }
    }

    /// Called when the talk mode changes while connected.
    func applyTalkModeChange() async {
        if Settings.talkMode.needsMicrophone {
            await armMicrophone()
            if Settings.talkMode == .open { await startTalking() }
            else if isTalking { await stopTalking() }
        } else {
            await disarmMicrophone()
            // Back to .playback so the earbuds return to full-bandwidth audio.
            try? configureAudioSession(forTalking: false)
        }
    }
}

extension CommsClient: RoomDelegate {
    nonisolated func room(_: Room, didUpdateConnectionState state: ConnectionState, from _: ConnectionState) {
        Task { @MainActor in
            switch state {
            case .connected: self.state = .listening
            case .reconnecting: self.state = .reconnecting
            case .disconnected:
                if self.shouldBeConnected {
                    // The publication does not survive the drop. Clearing it
                    // is what lets arming run again on reconnect — otherwise
                    // armMicrophone() sees a stale non-nil publication, returns
                    // early, and the beltpack comes back able to listen but
                    // silently unable to talk.
                    self.micPublication = nil
                    self.micTrack = nil
                    self.isTalking = false
                    self.scheduleReconnect(reason: "connection lost")
                }
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
        Task { @MainActor in
            self.refreshTalkers(room)
            // A track arriving later must not come in at unity when the
            // operator has already turned things down.
            self.applyListenVolume()
        }
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
