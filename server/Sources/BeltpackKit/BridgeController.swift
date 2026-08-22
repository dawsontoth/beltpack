#if os(macOS)

import Foundation
import LiveKit
import OSLog

/// One participant as the operator needs to see them.
public struct ParticipantInfo: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let isMuted: Bool
    public let isSpeaking: Bool
    public let publishesAudio: Bool
    public let isBridge: Bool
}

/// Drives the bridge and publishes everything a UI needs to show.
///
/// Lives in the library rather than the app so the headless bridge and the
/// Mac app cannot drift apart on how a device is chosen or a room is joined.
@MainActor
public final class BridgeController: ObservableObject {
    public enum RunState: Equatable, Sendable {
        case stopped
        case starting
        case running
        case failed(String)

        public var isBusy: Bool { self == .starting }
        public var isRunning: Bool { self == .running }
    }

    @Published public private(set) var runState: RunState = .stopped
    @Published public private(set) var participants: [ParticipantInfo] = []
    @Published public private(set) var inputs: [AudioInput] = []
    @Published public private(set) var outputs: [AudioInput] = []
    @Published public private(set) var micStatus: String = Microphone.statusDescription

    /// Chosen in the UI. Applied when the bridge starts, and applied live
    /// while it is running so an operator can re-patch mid-service.
    @Published public var selectedInput: AudioInput? { didSet { applyInput() } }
    @Published public var selectedOutput: AudioInput? { didSet { applyOutput() } }

    public var config: Config?

    private let room = Room()
    private var publication: LocalTrackPublication?

    // A bundled app has nowhere to print to. Everything diagnostic goes to
    // the unified log, readable with:
    //   log stream --predicate 'subsystem == "org.beltpack"'
    private let log = Logger(subsystem: "org.beltpack", category: "bridge")

    public init() {
        room.add(delegate: self)
        refreshDevices()
    }

    // MARK: - Devices

    public func refreshDevices() {
        inputs = AudioDevices.list(.input)
        outputs = AudioDevices.list(.output)
        micStatus = Microphone.statusDescription

        let defaultIn = AudioDevices.currentDefaultInput()
        let defaultOut = AudioDevices.currentDefaultOutput()
        if selectedInput == nil { selectedInput = inputs.first { $0.id == defaultIn } ?? inputs.first }
        if selectedOutput == nil { selectedOutput = outputs.first { $0.id == defaultOut } ?? outputs.first }
    }

    public func requestMicrophoneAccess() async {
        _ = await Microphone.ensureAccess()
        micStatus = Microphone.statusDescription
        refreshDevices()
    }

    private func applyInput() {
        guard let device = selectedInput else { return }
        try? AudioDevices.setDefault(device, direction: .input)
    }

    private func applyOutput() {
        guard let device = selectedOutput else { return }
        try? AudioDevices.setDefault(device, direction: .output)
    }

    // MARK: - Running

    public func start() async {
        guard case .stopped = runState else { return }
        guard let config else {
            log.error("start refused: no configuration loaded")
            runState = .failed("No configuration loaded.")
            return
        }
        guard await Microphone.ensureAccess() else {
            micStatus = Microphone.statusDescription
            log.error("start refused: microphone \(Microphone.statusDescription, privacy: .public)")
            runState = .failed("Microphone access is required to capture the console.")
            return
        }

        runState = .starting
        log.notice("starting room \(config.room, privacy: .public) at \(config.livekitURL, privacy: .public)")
        log.notice("input \(self.selectedInput?.name ?? "none", privacy: .public), output \(self.selectedOutput?.name ?? "none", privacy: .public)")
        applyInput()
        if config.subscribes { applyOutput() }

        do {
            let token = try AccessToken.mint(
                apiKey: config.apiKey,
                apiSecret: config.apiSecret,
                identity: config.identity,
                grants: .init(room: config.room, canPublish: true, canSubscribe: config.subscribes),
            )
            try await room.connect(
                url: config.livekitURL,
                token: token,
                roomOptions: RoomOptions(adaptiveStream: false, dynacast: false),
            )

            // A console feed, not someone talking into a phone: every voice
            // processing effect off. Gain staging belongs on the WING.
            let track = LocalAudioTrack.createTrack(
                name: "console",
                options: AudioCaptureOptions(
                    echoCancellation: false,
                    autoGainControl: false,
                    noiseSuppression: false,
                    highpassFilter: false,
                    typingNoiseDetection: false,
                ),
            )
            publication = try await room.localParticipant.publish(audioTrack: track)
            runState = .running
            log.notice("running: publishing console feed")
            refreshParticipants()
        } catch {
            log.error("start failed: \(error.localizedDescription, privacy: .public)")
            runState = .failed(error.localizedDescription)
            await room.disconnect()
        }
    }

    public func stop() async {
        if let publication {
            try? await room.localParticipant.unpublish(publication: publication)
        }
        publication = nil
        await room.disconnect()
        participants = []
        runState = .stopped
    }

    // MARK: - Participants

    private func refreshParticipants() {
        let bridgeIdentity = config?.identity
        participants = room.remoteParticipants.values.map { participant in
            let audio = participant.audioTracks.first
            let identity = participant.identity?.stringValue ?? "unknown"
            return ParticipantInfo(
                id: identity,
                name: participant.name?.isEmpty == false ? participant.name! : identity,
                // No audio track at all reads as muted to an operator; the
                // distinction between "unpublished" and "published but muted"
                // is not one they need to care about.
                isMuted: audio?.isMuted ?? true,
                isSpeaking: participant.isSpeaking,
                publishesAudio: audio != nil,
                isBridge: identity == bridgeIdentity,
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

extension BridgeController: RoomDelegate {
    public nonisolated func room(_: Room, participantDidConnect _: RemoteParticipant) {
        Task { @MainActor in self.refreshParticipants() }
    }

    public nonisolated func room(_: Room, participantDidDisconnect _: RemoteParticipant) {
        Task { @MainActor in self.refreshParticipants() }
    }

    public nonisolated func room(_: Room, participant _: Participant, trackPublication _: TrackPublication, didUpdateIsMuted _: Bool) {
        Task { @MainActor in self.refreshParticipants() }
    }

    public nonisolated func room(_: Room, didUpdateSpeakingParticipants _: [Participant]) {
        Task { @MainActor in self.refreshParticipants() }
    }

    public nonisolated func room(_: Room, participant _: RemoteParticipant, didPublishTrack _: RemoteTrackPublication) {
        Task { @MainActor in self.refreshParticipants() }
    }

    public nonisolated func room(_: Room, participant _: RemoteParticipant, didUnpublishTrack _: RemoteTrackPublication) {
        Task { @MainActor in self.refreshParticipants() }
    }

    public nonisolated func room(_: Room, didDisconnectWithError error: LiveKitError?) {
        Task { @MainActor in
            if let error, self.runState.isRunning {
                self.runState = .failed(error.localizedDescription)
            }
        }
    }
}

#endif
