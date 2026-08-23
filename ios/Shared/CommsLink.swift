import Foundation

/// The contract between phone and watch.
///
/// The watch is a remote control, not a second client. The phone owns the
/// LiveKit connection and the audio session, and the earbuds are paired to it —
/// a second independent connection would fight for the Bluetooth route and
/// could drag the earbuds into hands-free mode behind the phone's back.
///
/// So the watch sends intent and renders state it is told. It never decides
/// whether it is transmitting.
enum CommsLink {
    static let actionKey = "action"
    static let snapshotKey = "snapshot"

    enum Action: String, Codable {
        case status
        case startTalking
        case stopTalking
        case toggleTalking
    }
}

/// What the watch is allowed to believe.
///
/// Sent by the phone rather than inferred on the wrist: a watch that shows
/// "talking" because a button was pressed, when the phone never opened the
/// mic, is worse than a watch that shows nothing.
struct CommsSnapshot: Codable, Equatable, Sendable {
    var isConnected: Bool
    var isTalking: Bool
    var consoleIsLive: Bool
    var talkMode: String
    var status: String

    static let unknown = CommsSnapshot(
        isConnected: false,
        isTalking: false,
        consoleIsLive: false,
        talkMode: TalkMode.pushToTalk.rawValue,
        status: "Not connected",
    )

    var mode: TalkMode { TalkMode(rawValue: talkMode) ?? .pushToTalk }

    /// Talk is only meaningful when the phone is on comms and in a mode where
    /// a button does anything.
    var canTalk: Bool {
        isConnected && mode.needsMicrophone && mode != .open
    }

    func encoded() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [CommsLink.snapshotKey: data]
    }

    static func decoded(from message: [String: Any]) -> CommsSnapshot? {
        guard let data = message[CommsLink.snapshotKey] as? Data else { return nil }
        return try? JSONDecoder().decode(CommsSnapshot.self, from: data)
    }
}
