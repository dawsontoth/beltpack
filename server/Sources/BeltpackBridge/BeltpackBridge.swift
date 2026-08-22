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
            printDevices()
            return
        }

        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("beltpack-bridge: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func printDevices() {
        let devices = AudioDevices.list()
        guard !devices.isEmpty else {
            print("No Core Audio input devices found.")
            return
        }
        print("Core Audio inputs (\(devices.count)):")
        for device in devices {
            let name = device.name.isEmpty ? "<no name — grant Microphone permission>" : device.name
            print("  \(name)\(device.isDefault ? "  (default)" : "")  [id: \(device.deviceId)]")
        }
    }

    private static func run() async throws {
        let config = try Config.fromEnvironment()

        let device = try AudioDevices.select(matching: config.inputDeviceHint)
        log("capturing from \(device.name)")

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
