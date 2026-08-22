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

        let device = try AudioDevices.select(matching: config.inputDeviceHint)
        log("capturing from \(device.name) (\(device.channels) ch)")

        // Phase 2 return leg: subscribed phone audio plays out of the system
        // default output, so point that at the WING channel feeding Bus 1.
        // The console keeps it out of Bus 2 — that is the mix-minus that stops
        // phone users hearing themselves a quarter-second late.
        if config.subscribes {
            guard let outputHint = config.outputDeviceHint else {
                throw BridgeError.missingOutputDevice
            }
            let output = try AudioDevices.select(matching: outputHint, direction: .output)
            log("returning phone audio to \(output.name) (\(output.channels) ch)")
        }

        let token = try AccessToken.mint(
            apiKey: config.apiKey,
            apiSecret: config.apiSecret,
            identity: config.identity,
            grants: .init(
                room: config.room,
                canPublish: true,
                canSubscribe: config.subscribes,
            ),
        )

        let room = Room()
        try await room.connect(
            url: config.livekitURL,
            token: token,
            roomOptions: RoomOptions(adaptiveStream: false, dynacast: false),
        )
        log("connected to \(config.room) at \(config.livekitURL)")

        // This is a console feed, not somebody talking into a phone. Every piece
        // of voice processing WebRTC would helpfully apply — echo cancellation,
        // noise suppression, gain riding — actively damages it, so all of it is
        // off. Gain staging belongs on the WING, where you can see it.
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

        // Logged before the publish, not after: if the device reports a valid
        // format but fails when AVAudioEngine actually opens it, the process
        // dies here with an uncaught ObjC exception and this is the last line
        // in the log. It names the culprit.
        log("opening \(device.name) for capture…")
        _ = try await room.localParticipant.publish(audioTrack: track)
        log("publishing — beltpacks can join")

        // Nothing else to do on this thread; the SDK owns the audio path.
        // Park forever so launchd keeps us alive.
        while true {
            try await Task.sleep(for: .seconds(3600))
        }
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
