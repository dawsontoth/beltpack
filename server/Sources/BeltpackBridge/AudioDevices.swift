import Foundation
import LiveKit

/// Picking which Core Audio device feeds the room.
///
/// The WING presents as a single 48-in / 48-out class-compliant device, and
/// WebRTC's audio device module captures its *first* channels. To send a
/// specific console bus, build an Aggregate Device in Audio MIDI Setup that
/// exposes only the pair you want and point `BELTPACK_INPUT_DEVICE` at that
/// instead. See deploy/README.md.
enum AudioDevices {
    static func list() -> [AudioDevice] {
        AudioManager.shared.inputDevices
    }

    /// Case-insensitive substring match, so "wing" finds "WING 48ch".
    static func select(matching hint: String) throws -> AudioDevice {
        let devices = list()
        let needle = hint.lowercased()

        guard let match = devices.first(where: { $0.name.lowercased().contains(needle) }) else {
            throw AudioDeviceError.notFound(hint: hint, available: devices.map(\.name))
        }

        AudioManager.shared.inputDevice = match
        return match
    }
}

enum AudioDeviceError: LocalizedError {
    case notFound(hint: String, available: [String])

    var errorDescription: String? {
        switch self {
        case let .notFound(hint, available):
            let list = available.isEmpty
                ? "  (none — is the WING powered on and the USB cable in a direct port, not a hub?)"
                : available.map { "  - \($0)" }.joined(separator: "\n")
            return """
            No input device matching "\(hint)".
            Available inputs:
            \(list)
            """
        }
    }
}
