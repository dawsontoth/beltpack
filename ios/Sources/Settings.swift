import BeltpackKit
import Foundation

/// Where this beltpack points and who it says it is.
///
/// Stored in UserDefaults so a volunteer sets it once. The passcode is the
/// only gate on the token service — this is a comms channel on a private
/// VLAN, not a bank.
///
/// These are computed rather than stored so they stay clear of Swift 6's
/// global-mutable-state rules; UserDefaults is the actual storage.
enum Settings {
    enum Key {
        static let serverURL = "beltpack.serverURL"
        static let identity = "beltpack.identity"
        static let passcode = "beltpack.passcode"
        static let talkMode = "beltpack.talkMode"
        static let listenVolume = "beltpack.listenVolume"
        static let micGain = "beltpack.micGain"
        static let muteTone = "beltpack.muteTone"
        static let outputMode = "beltpack.outputMode"
        static let micInput = "beltpack.micInput"
        static let presets = "beltpack.presets"
    }

    static let defaultServerURL = "https://comms.example.org"

    static var serverURL: String {
        get { UserDefaults.standard.string(forKey: Key.serverURL) ?? defaultServerURL }
        set { UserDefaults.standard.set(newValue, forKey: Key.serverURL) }
    }

    static var identity: String {
        get { UserDefaults.standard.string(forKey: Key.identity) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Key.identity) }
    }

    static var passcode: String {
        get { UserDefaults.standard.string(forKey: Key.passcode) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Key.passcode) }
    }

    static var talkMode: TalkMode {
        get { TalkMode(rawValue: UserDefaults.standard.string(forKey: Key.talkMode) ?? "") ?? .pushToTalk }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.talkMode) }
    }

    /// Personal trims, unity at 1.0. Capped at 2 rather than the SDK's 10:
    /// past a modest boost you are amplifying room noise, and on comms that
    /// is everyone's problem rather than only your own.
    static let gainRange: ClosedRange<Double> = 0 ... 2

    static var listenVolume: Double {
        get { number(Key.listenVolume) }
        set { UserDefaults.standard.set(newValue, forKey: Key.listenVolume) }
    }

    static var micGain: Double {
        get { number(Key.micGain) }
        set { UserDefaults.standard.set(newValue, forKey: Key.micGain) }
    }

    private static func number(_ key: String) -> Double {
        // An absent key reads as 0, which would silently mute somebody.
        guard UserDefaults.standard.object(forKey: key) != nil else { return 1 }
        return UserDefaults.standard.double(forKey: key).clamped(to: gainRange)
    }

    /// Whether iOS plays its tone when the microphone mutes and unmutes.
    ///
    /// Off by default. The tone comes from the SDK's default mute mode, which
    /// also happens to be the one that reconfigures more on each toggle; the
    /// silent mode is both quieter and lighter. The visible trade is that the
    /// orange microphone indicator stays lit while muted — which is arguably
    /// more honest, since the mic really is armed and waiting.
    static var muteTone: Bool {
        get { UserDefaults.standard.object(forKey: Key.muteTone) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Key.muteTone) }
    }

    static var outputMode: AudioOutputMode {
        get { AudioOutputMode(rawValue: UserDefaults.standard.string(forKey: Key.outputMode) ?? "") ?? .automatic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.outputMode) }
    }

    static var micInput: MicInput {
        get { MicInput(stored: UserDefaults.standard.string(forKey: Key.micInput) ?? "") }
        set { UserDefaults.standard.set(newValue.stored, forKey: Key.micInput) }
    }

    /// The announcement buttons. Editable, because every room has its own
    /// shorthand and a preset somebody would not say is just a button in the
    /// way.
    static var presets: [String] {
        get {
            let stored = UserDefaults.standard.stringArray(forKey: Key.presets)
            return stored ?? AnnouncementPreset.defaults
        }
        set {
            let cleaned = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            UserDefaults.standard.set(cleaned, forKey: Key.presets)
        }
    }

    static func resetPresets() {
        UserDefaults.standard.removeObject(forKey: Key.presets)
    }

    /// Applies a scanned pairing code.
    ///
    /// Whole or not at all — `PairingLink` refuses a half-configured link, so
    /// nothing here can leave somebody staring at a form that looks filled in
    /// and cannot connect. The server is normalised on the way in rather than
    /// only on the way out, so what Settings shows is what will be used.
    ///
    /// Takes a store so it can be tested without trampling the real defaults.
    @discardableResult
    static func apply(_ link: PairingLink, to defaults: UserDefaults = .standard) -> Bool {
        let normalised = ServerAddress.normalize(link.server)?.absoluteString
            ?? link.server.trimmingCharacters(in: .whitespacesAndNewlines)

        defaults.set(normalised, forKey: Key.serverURL)
        defaults.set(link.passcode, forKey: Key.passcode)
        if let identity = link.identity, !identity.isEmpty {
            defaults.set(identity, forKey: Key.identity)
        }

        let identity = defaults.string(forKey: Key.identity) ?? ""
        return !identity.isEmpty && !link.passcode.isEmpty && ServerAddress.normalize(normalised) != nil
    }

    static var isConfigured: Bool {
        !identity.isEmpty && !passcode.isEmpty && resolvedServerURL != nil
    }

    /// What `serverURL` actually resolves to once tidied up.
    static var resolvedServerURL: URL? {
        ServerAddress.normalize(serverURL)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
