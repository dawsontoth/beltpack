import BeltpackKit
import Foundation
import LiveKit

/// Publishes one WING console bus into a LiveKit room as an Opus track.
///
/// Phase 1 is one-way: the console mixes, this only transports. The bridge
/// never mixes anything itself — see the room's mix-minus note in README.md.
@main
struct BeltpackBridge {
    static func main() async {
        // stdout is block-buffered when it points at a file, which under
        // launchd means the log stays empty until the buffer fills — exactly
        // when you most need to read it. Line-buffer it instead.
        setvbuf(stdout, nil, _IOLBF, 0)

        // `--devices` lists Core Audio inputs and exits, so you can find the
        // WING's exact name without booting the whole bridge.
        if CommandLine.arguments.contains("--devices") {
            await printDevices()
            return
        }

        if CommandLine.arguments.contains("--pair") {
            printPairingCode()
            return
        }

        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("beltpack-bridge: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    /// Prints a scannable pairing code so nobody types a server address or a
    /// passcode into a phone by hand.
    private static func printPairingCode() {
        let config: Config
        do {
            config = try Config.fromEnvironment()
        } catch {
            FileHandle.standardError.write(Data("beltpack-bridge: \(error.localizedDescription)\n".utf8))
            exit(1)
        }

        guard let clientURL = config.clientURL, let passcode = config.passcode else {
            FileHandle.standardError.write(Data("""
            Set BELTPACK_CLIENT_URL and BELTPACK_PASSCODE in .env to build a pairing code.
            `scripts/setup.sh --lan` fills the first one in for you.

            """.utf8))
            exit(1)
        }

        let link = PairingLink(server: clientURL, passcode: passcode)
        let wantsWeb = CommandLine.arguments.contains("--web")

        // Two forms, because one code cannot serve both platforms: the app
        // scheme opens the iOS app, the https form opens the web client.
        guard let url = wantsWeb ? link.webURL : link.appURL,
              let matrix = QRCode.matrix(for: url.absoluteString)
        else {
            FileHandle.standardError.write(Data("beltpack-bridge: could not build a pairing code\n".utf8))
            exit(1)
        }

        print()
        print(wantsWeb ? "  Android and laptops — scan or open:" : "  iPhone — scan with the camera:")
        print()
        print(QRCode.terminalRendering(matrix))
        print("  \(url.absoluteString)")
        print()
        print("  This code contains the passcode. Treat a printed one as a key:")
        print("  anyone who photographs it is on comms.")
        print()
        if !wantsWeb {
            print("  For Android, run: beltpack-bridge --pair --web")
            print()
        }
    }

    private static func printDevices() async {
        // Ask first. Enumerating alone never prompts, it just hands back
        // redacted names, which looks exactly like having no hardware.
        _ = await Microphone.ensureAccess()
        print("Microphone access: \(Microphone.statusDescription)")

        let devices = AudioDevices.list()
        guard !devices.isEmpty else {
            print("No Core Audio input devices found.")
            return
        }
        let currentIn = AudioDevices.currentDefaultInput()
        print("Core Audio inputs (\(devices.count)):")
        for device in devices {
            let marker = device.id == currentIn ? "  (current default)" : ""
            // Channel count is how you spot the console at a glance: the WING
            // reports 48 in, everything else on a Mac reports 1 or 2.
            print("  \(device.name)  —  \(device.channels) in\(marker)")
        }

        // Outputs matter once BELTPACK_SUBSCRIBE is on: that is where the
        // summed phone audio goes back to the console.
        let outputs = AudioDevices.list(.output)
        let currentOut = AudioDevices.currentDefaultOutput()
        print("\nCore Audio outputs (\(outputs.count)):")
        for device in outputs {
            let marker = device.id == currentOut ? "  (current default)" : ""
            print("  \(device.name)  —  \(device.channels) out\(marker)")
        }
    }

    private static func run() async throws {
        let config = try Config.fromEnvironment()

        guard await Microphone.ensureAccess() else {
            throw BridgeError.microphoneUnavailable
        }

        // Resolve devices up front, so a bad hint fails immediately with a list
        // of what is actually attached rather than at reconnect time.
        let input = try AudioDevices.select(matching: config.inputDeviceHint)
        log("capturing from \(input.name) (\(input.channels) ch)")

        if config.subscribes {
            guard let hint = config.outputDeviceHint else {
                throw BridgeError.missingOutputDevice
            }
            let output = try AudioDevices.select(matching: hint, direction: .output)
            log("returning phone audio to \(output.name) (\(output.channels) ch)")
        }

        // The same trim the Mac app applies, so a headless bridge and a
        // supervised one sound the same.
        if config.inputGain != 0 {
            let capture = CaptureGain(gain: AudioMeter.gain(decibels: config.inputGain))
            AudioManager.shared.capturePostProcessingDelegate = capture
            log("console feed trim \(Int(config.inputGain)) dB")
        }

        // Before anything builds an audio engine: a console puts 48 channels
        // down one cable and WebRTC would otherwise take whichever comes
        // first. Chained ahead of the SDK's own mixer rather than replacing
        // it, since that is what set(engineObservers:) does to the list.
        let channels = ChannelSelection(
            inputChannel: config.inputChannel,
            outputChannel: config.outputChannel,
        )
        if channels.isActive {
            AudioManager.shared.set(engineObservers: [channels, AudioManager.shared.mixer])
            log("channel map: input \(config.inputChannel.map(String.init) ?? "default"), output \(config.outputChannel.map(String.init) ?? "default")")
        }

        // Deliberately not the Mac app's BridgeController: that type is
        // @MainActor, and creating a Room under main-actor isolation in a
        // process with no app run loop wedges a WebRTC signalling thread. The
        // GUI is fine; a command-line tool is not.
        var attempt = 0
        while true {
            do {
                try await connectAndPublish(config: config)
                attempt = 0
                log("publishing — beltpacks can join")

                // Hold here until the connection drops.
                try await waitForDisconnect()
                log("connection lost — retrying")
            } catch {
                log("connect failed: \(error.localizedDescription)")
            }

            attempt += 1
            let delay = min(pow(2.0, Double(attempt - 1)), 15)
            try await Task.sleep(for: .seconds(delay))
        }
    }

    private static let room = Room()
    private static let watcher = DisconnectWatcher()

    private static func connectAndPublish(config: Config) async throws {
        let token = try AccessToken.mint(
            apiKey: config.apiKey,
            apiSecret: config.apiSecret,
            identity: config.identity,
            grants: .init(room: config.room, canPublish: true, canSubscribe: config.subscribes),
        )

        await room.add(delegate: watcher)
        await watcher.reset()

        try await room.connect(
            url: config.livekitURL,
            token: token,
            roomOptions: RoomOptions(adaptiveStream: false, dynacast: false),
        )
        log("connected to \(config.room) at \(config.livekitURL)")

        // A console feed, not somebody talking into a phone: every voice
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
        log("opening \(config.inputDeviceHint) for capture…")
        _ = try await room.localParticipant.publish(
            audioTrack: track,
            // DTX off. It is built for a talking head, and on a programme feed
            // it replaces silence with periodic comfort noise and clips the
            // front of anything that follows. A console bus should go out
            // continuously, quiet passages included.
            options: AudioPublishOptions(dtx: false),
        )
    }

    private static func waitForDisconnect() async throws {
        // Poll rather than bridge a delegate callback into a continuation:
        // a missed or doubled resume here would either wedge the bridge or
        // crash it, and neither is worth the elegance.
        while await !watcher.didDisconnect {
            try await Task.sleep(for: .seconds(1))
        }
        await room.disconnect()
    }

    private static func log(_ message: String) {
        print("beltpack-bridge: \(message)")
    }
}

enum BridgeError: LocalizedError {
    case microphoneUnavailable
    case missingOutputDevice

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable:
            "cannot capture without microphone access (see the guidance above)"
        case .missingOutputDevice:
            "BELTPACK_SUBSCRIBE is on, so set BELTPACK_OUTPUT_DEVICE to the WING channel that feeds Bus 1"
        }
    }
}
