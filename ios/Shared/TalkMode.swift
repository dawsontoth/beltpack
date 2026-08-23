import Foundation

/// When the microphone is actually live.
enum TalkMode: String, CaseIterable, Identifiable, Sendable {
    /// Never transmit. The only mode that keeps Bluetooth in A2DP for the
    /// whole service, because arming the mic at all forces the route change.
    case listenOnly
    /// Hold the button. Safest in a live room.
    case pushToTalk
    /// Tap on, tap off.
    case latch
    /// Always transmitting. Convenient, and one rustling pocket away from
    /// being everyone's problem.
    case open

    var id: String { rawValue }

    /// Whether the mic gets armed at connect. Arming is what costs the
    /// Bluetooth route change, so it is worth not doing when nobody will talk.
    var needsMicrophone: Bool { self != .listenOnly }

    var title: String {
        switch self {
        case .listenOnly: "Listen only"
        case .pushToTalk: "Push to talk"
        case .latch: "Latch"
        case .open: "Open mic"
        }
    }
}
