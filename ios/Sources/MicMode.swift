import AVFAudio
import Foundation

/// How the beltpack captures your voice, and what it costs.
///
/// Asking iOS for the *headset's* microphone forces Bluetooth into hands-free
/// mode: both directions drop to 16 kHz mono, the console feed included, and
/// you get back roughly 30 ms of latency plus the use of both hands. Using the
/// phone's own mic keeps the earbuds in A2DP/AAC at full bandwidth, but you
/// have to hold the handset to talk.
///
/// Default is the headset, because on comms a cue heard 30 ms sooner beats a
/// cue heard in higher fidelity, and a camera operator needs their hands.
enum MicMode: String, CaseIterable, Identifiable, Sendable {
    /// Phone mic, earbuds stay in high quality. You talk into the handset.
    case phoneMic
    /// Headset mic, hands free, everything drops to call quality.
    case headsetMic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phoneMic: "Phone mic"
        case .headsetMic: "Headset mic"
        }
    }

    var detail: String {
        switch self {
        case .phoneMic:
            "Best sound: earbuds stay in high quality, but you talk into the phone."
        case .headsetMic:
            "Lowest latency and hands free. Everything drops to call quality while you are on."
        }
    }

    var sessionOptions: AVAudioSession.CategoryOptions {
        switch self {
        case .phoneMic:
            // A2DP only. Deliberately not .allowBluetooth, which is what
            // requests HFP and collapses the audio quality.
            [.allowBluetoothA2DP, .defaultToSpeaker]
        case .headsetMic:
            [.allowBluetoothHFP, .allowBluetoothA2DP]
        }
    }

    var sessionMode: AVAudioSession.Mode {
        switch self {
        case .phoneMic: .default
        case .headsetMic: .voiceChat
        }
    }
}

/// When the microphone is actually live.
enum TalkMode: String, CaseIterable, Identifiable, Sendable {
    /// Hold the button. Safest in a live room.
    case pushToTalk
    /// Tap on, tap off.
    case latch
    /// Always transmitting. Convenient, and one rustling pocket away from
    /// being everyone's problem.
    case open

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pushToTalk: "Push to talk"
        case .latch: "Latch"
        case .open: "Open mic"
        }
    }
}
