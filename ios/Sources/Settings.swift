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
    private enum Key {
        static let serverURL = "beltpack.serverURL"
        static let identity = "beltpack.identity"
        static let passcode = "beltpack.passcode"
        static let micMode = "beltpack.micMode"
        static let talkMode = "beltpack.talkMode"
        static let listenVolume = "beltpack.listenVolume"
        static let micGain = "beltpack.micGain"
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

    /// Defaults to the headset: on comms, latency and free hands beat fidelity.
    /// Switch to `.phoneMic` when sound quality matters more than either.
    static var micMode: MicMode {
        get { MicMode(rawValue: UserDefaults.standard.string(forKey: Key.micMode) ?? "") ?? .headsetMic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.micMode) }
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
