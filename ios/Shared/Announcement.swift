import Foundation

/// A spoken announcement, and the text of it.
///
/// The text travels over the room's data channel and the audio over the
/// sender's own microphone track. Two paths for one event, because the text
/// has to reach people whose mode or earbuds mean they will not hear it —
/// somebody in listen-only with a phone in a pocket still needs to know a cue
/// went out.
struct Announcement: Codable, Identifiable, Equatable, Sendable {
    static let topic = "beltpack.announcement"

    var id: UUID
    var text: String
    var sender: String
    var sentAt: Date

    init(id: UUID = UUID(), text: String, sender: String, sentAt: Date = Date()) {
        self.id = id
        self.text = text
        self.sender = sender
        self.sentAt = sentAt
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decoded(_ data: Data) -> Announcement? {
        try? JSONDecoder().decode(Announcement.self, from: data)
    }
}

/// The buttons on the announcement screen.
///
/// Deliberately short: these get pressed by somebody holding a camera, and a
/// long phrase takes long enough to speak that it stops being a cue and starts
/// being an interruption.
enum AnnouncementPreset {
    static let all: [String] = [
        "Standby",
        "We are live",
        "Two minutes",
        "Ready when you are",
        "Hold please",
        "That's a wrap",
    ]
}
