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
        case reconnecting
        case failed(String)

        public var isBusy: Bool { self == .starting || self == .reconnecting }
        public var isRunning: Bool { self == .running }
        /// Whether the bridge believes it should be on air, whether or not it
        /// currently is. Used to decide if a drop deserves a retry.
        public var wantsToRun: Bool { self != .stopped }
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

    /// Where `config` came from, so the control panel can write a change back
    /// to the same file rather than only holding it until the next restart.
    public var envURL: URL?

    /// Settings the panel can change. Held here rather than read from `config`
    /// each time, because `config` is a snapshot of the file as it was read.
    @Published public private(set) var inputChannel: Int?
    @Published public private(set) var outputChannel: Int?
    @Published public private(set) var canPublish: Bool = true

    /// Trim on the console feed, in decibels. Held as decibels because that is
    /// what it is set in; the processor keeps the multiplier.
    @Published public private(set) var inputGain: Double = 0

    /// How loud the console feed actually is, 0…1 on a dBFS scale. Without
    /// this the gain is set by ear over a headset in another room.
    public var inputLevel: Float { captureGain.level }

    private let captureGain = CaptureGain()

    private let room = Room()
    private var publication: LocalTrackPublication?

    // A bundled app has nowhere to print to. Everything diagnostic goes to
    // the unified log, readable with:
    //   log stream --predicate 'subsystem == "org.beltpack"'
    private let log = Logger(subsystem: "org.beltpack", category: "bridge")

    /// Set while the bridge is meant to be on air. A drop is only worth
    /// retrying if nobody asked it to stop.
    private var shouldRun = false
    private var reconnectTask: Task<Void, Never>?

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

    /// Which channel of the selected device carries comms. Read before the
    /// engine exists, so it has to happen ahead of connecting rather than when
    /// a device is picked.
    /// Installs the trim on the capture path. Set once; the multiplier is
    /// changed in place afterwards.
    private func applyCaptureGain() {
        AudioManager.shared.capturePostProcessingDelegate = captureGain
    }

    private func applyChannelMap() {
        let channels = ChannelSelection(inputChannel: inputChannel, outputChannel: outputChannel)
        guard channels.isActive else { return }
        // Chained ahead of the SDK's mixer rather than replacing it:
        // set(engineObservers:) overwrites the whole list.
        AudioManager.shared.set(engineObservers: [channels, AudioManager.shared.mixer])
    }

    /// Takes the settings the panel can change out of the loaded config. Call
    /// after assigning `config`.
    public func adoptConfig() {
        inputChannel = config?.inputChannel
        outputChannel = config?.outputChannel
        canPublish = config?.canPublish ?? true
        inputGain = config?.inputGain ?? 0
        captureGain.gain = AudioMeter.gain(decibels: inputGain)
    }

    /// Changes the trim on the console feed, and writes it back to `.env`.
    ///
    /// Takes effect on the next buffer — nothing restarts, because the
    /// processor is already in the path and only its multiplier changes.
    public func setInputGain(_ decibels: Double) throws {
        inputGain = decibels
        captureGain.gain = AudioMeter.gain(decibels: decibels)
        try persist(["BELTPACK_INPUT_GAIN": String(format: "%.0f", decibels)])
        log.notice("console feed trim set to \(decibels, privacy: .public) dB")
    }

    /// Changes which channels carry comms, and writes it back to `.env`.
    ///
    /// The map is applied when the audio engine is built, so a running bridge
    /// has to be restarted for it to mean anything. Doing that here rather than
    /// leaving it to the operator: a control that appears to work and silently
    /// does not until something else happens is worse than a short dropout.
    public func setChannels(input: Int?, output: Int?) async throws {
        inputChannel = input
        outputChannel = output
        try persist([
            "BELTPACK_INPUT_CHANNEL": input.map(String.init) ?? "",
            "BELTPACK_OUTPUT_CHANNEL": output.map(String.init) ?? "",
        ])
        log.notice("channels set to input \(input.map(String.init) ?? "default", privacy: .public), output \(output.map(String.init) ?? "default", privacy: .public)")

        if runState.wantsToRun {
            await stop()
            await start()
        }
    }

    /// Turns talking on or off for every phone.
    ///
    /// Only written to `.env`: the token service is what enforces it, and it
    /// reads the file when it mints. Nothing here needs restarting, but a phone
    /// already holding a token keeps what it was given until it rejoins.
    public func setCanPublish(_ allowed: Bool) throws {
        canPublish = allowed
        try persist(["BELTPACK_CAN_PUBLISH": allowed ? "true" : "false"])
        log.notice("phones may talk: \(allowed, privacy: .public)")
    }

    private func persist(_ values: [String: String]) throws {
        guard let envURL else { throw BridgeControllerError.noEnvFile }
        try EnvFile.update(envURL, values)
    }

    // MARK: - Running

    public func start() async {
        guard case .stopped = runState else { return }
        shouldRun = true
        applyCaptureGain()
        applyChannelMap()
        await connectAndPublish()
    }

    private func connectAndPublish() async {
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
            await room.disconnect()
            // A server that is down now may be up in a moment; only give up
            // for good if somebody asked us to stop.
            if shouldRun {
                scheduleReconnect(reason: error.localizedDescription)
            } else {
                runState = .failed(error.localizedDescription)
            }
        }
    }

    /// Retries with backoff. A LiveKit restart, a Mac waking, or services
    /// coming up in the wrong order all leave the bridge connected to nothing;
    /// without this it sits there looking healthy while comms is dead.
    private func scheduleReconnect(reason: String) {
        guard shouldRun, reconnectTask == nil else { return }
        runState = .reconnecting
        log.error("disconnected (\(reason, privacy: .public)) — retrying")

        reconnectTask = Task { [weak self] in
            var delay: Double = 1
            while true {
                if Task.isCancelled { break }
                try? await Task.sleep(for: .seconds(delay))

                guard let self, await self.shouldRun else { break }
                await self.attemptReconnect()
                if await self.runState.isRunning { break }

                delay = min(delay * 2, 15)
            }
            await self?.clearReconnectTask()
        }
    }

    private func attemptReconnect() async {
        log.notice("reconnect attempt")
        await connectAndPublish()
    }

    private func clearReconnectTask() {
        reconnectTask = nil
    }

    public func stop() async {
        shouldRun = false
        reconnectTask?.cancel()
        reconnectTask = nil

        if let publication {
            try? await room.localParticipant.unpublish(publication: publication)
        }
        publication = nil
        await room.disconnect()
        participants = []
        runState = .stopped
        log.notice("stopped")
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
            guard self.shouldRun else { return }
            self.publication = nil
            self.participants = []
            self.scheduleReconnect(reason: error?.localizedDescription ?? "connection lost")
        }
    }
}

public enum BridgeControllerError: LocalizedError {
    case noEnvFile

    public var errorDescription: String? {
        switch self {
        case .noEnvFile:
            "No .env file to write to — choose one from the menu bar first."
        }
    }
}

#endif
