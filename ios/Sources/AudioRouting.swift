import AVFAudio
import Foundation

/// Where the console feed comes out.
///
/// iOS does not let an app pick an arbitrary output the way it can pick an
/// input — it can follow the system route or force the built-in speaker, and
/// that is all. So "off" is done by muting the incoming audio rather than by
/// choosing a route: the result a person wants is silence, and that is
/// reachable even when a route is not.
enum AudioOutputMode: String, CaseIterable, Identifiable, Sendable {
    /// Whatever is connected — earbuds, headphones, otherwise the speaker.
    case automatic
    /// Ignore a connected headset and use the phone's own speaker.
    case speaker
    /// Never make a sound. Announcements still arrive as notifications, which
    /// is the point: a position that should see cues without adding audio to
    /// the room.
    case silent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .speaker: "Phone speaker"
        case .silent: "Silent"
        }
    }

    var detail: String {
        switch self {
        case .automatic: "Earbuds or headphones if connected, otherwise the speaker."
        case .speaker: "Always the phone's own speaker, even with earbuds connected."
        case .silent: "Never plays audio. Announcements still arrive as notifications."
        }
    }
}

/// Which microphone to capture from.
///
/// Stored as a port UID so a choice survives the headset being unplugged and
/// plugged back in. Two reserved values carry the cases a UID cannot.
enum MicInput: Equatable, Sendable {
    /// Never arm the microphone. No talking, no microphone indicator, and
    /// Bluetooth stays in A2DP for the whole service.
    case off
    /// Let iOS choose, which in practice means a connected headset.
    case automatic
    /// A specific input port.
    case port(uid: String)

    static let offValue = "off"
    static let automaticValue = "automatic"

    init(stored: String) {
        switch stored {
        case Self.offValue: self = .off
        case Self.automaticValue, "": self = .automatic
        default: self = .port(uid: stored)
        }
    }

    var stored: String {
        switch self {
        case .off: Self.offValue
        case .automatic: Self.automaticValue
        case let .port(uid): uid
        }
    }

    var isOff: Bool { self == .off }
}

enum AudioRouting {
    /// Inputs iOS is currently offering. Empty until the session has been
    /// configured at least once, which is why the picker only fills in
    /// properly once the phone has been on comms.
    static func availableInputs() -> [AVAudioSessionPortDescription] {
        AVAudioSession.sharedInstance().availableInputs ?? []
    }

    /// The session options a chosen port implies.
    ///
    /// Asking for a Bluetooth port is what drags the link into hands-free mode
    /// and drops both directions to 16 kHz. Anything else can stay in A2DP, so
    /// the choice of microphone quietly decides what the console feed sounds
    /// like — which is why it is derived here rather than left to a
    /// separate setting somebody could set inconsistently.
    static func sessionOptions(for port: AVAudioSessionPortDescription?) -> AVAudioSession.CategoryOptions {
        guard let port else { return [.allowBluetoothHFP, .allowBluetoothA2DP] }
        return isBluetooth(port)
            ? [.allowBluetoothHFP, .allowBluetoothA2DP]
            : [.allowBluetoothA2DP, .defaultToSpeaker]
    }

    static func sessionMode(for port: AVAudioSessionPortDescription?) -> AVAudioSession.Mode {
        guard let port else { return .voiceChat }
        return isBluetooth(port) ? .voiceChat : .default
    }

    static func isBluetooth(_ port: AVAudioSessionPortDescription) -> Bool {
        [.bluetoothHFP, .bluetoothA2DP, .bluetoothLE].contains(port.portType)
    }

    static func port(matching uid: String) -> AVAudioSessionPortDescription? {
        availableInputs().first { $0.uid == uid }
    }
}
