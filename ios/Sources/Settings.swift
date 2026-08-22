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

    static var isConfigured: Bool {
        !identity.isEmpty && !passcode.isEmpty && URL(string: serverURL) != nil
    }
}
