import Foundation
import LiveKit

/// Publishes one WING console bus into a LiveKit room as an Opus track.
///
/// Phase 1 is one-way: the console mixes, this only transports. The bridge
/// never mixes anything itself — see the room's mix-minus note in README.md.
@main
struct BeltpackBridge {
    static func main() async {
        // `--devices` lists Core Audio inputs and exits, so you can find the
        // WING's exact name without booting the whole bridge.
        if CommandLine.arguments.contains("--devices") {
            await printDevices()
            return
        }

        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("beltpack-bridge: \(error.localizedDescription)\n".utf8))
            exit(1)
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
        let current = AudioDevices.currentDefaultInput()
        print("Core Audio inputs (\(devices.count)):")
        for device in devices {
            let marker = device.id == current ? "  (current default)" : ""
            // Channel count is how you spot the console at a glance: the WING
            // reports 48 in, everything else on a Mac reports 1 or 2.
            print("  \(device.name)  —  \(device.channels) in\(marker)")
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
