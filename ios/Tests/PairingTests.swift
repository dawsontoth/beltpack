import BeltpackKit
import Foundation
import Testing

@testable import Beltpack

/// Applying a scanned pairing code.
///
/// `PairingLink` parsing is covered in BeltpackKit; this is the other half —
/// what a scan actually does to this phone's settings.
@Suite("Pairing")
struct PairingTests {
    /// A throwaway store, so a test never touches the real settings.
    private func makeDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("a complete code fills everything in and reports ready")
    func completeCode() {
        let defaults = makeDefaults()
        let link = PairingLink(server: "172.16.1.41", passcode: "9qmbutqe38", identity: "Camera 2")

        #expect(Settings.apply(link, to: defaults) == true)
        #expect(defaults.string(forKey: Settings.Key.identity) == "Camera 2")
        #expect(defaults.string(forKey: Settings.Key.passcode) == "9qmbutqe38")
    }

    @Test("the server is normalised on the way in, not only on the way out")
    func normalisesServer() {
        let defaults = makeDefaults()
        // What a QR built from a bare LAN address carries.
        let link = PairingLink(server: "172.16.1.41", passcode: "x", identity: "Op")

        Settings.apply(link, to: defaults)
        // Stored ready to use, so Settings shows what will actually be used.
        #expect(defaults.string(forKey: Settings.Key.serverURL) == "http://172.16.1.41:7883")
    }

    @Test("a public hostname resolves to https rather than the local default")
    func publicHostname() {
        let defaults = makeDefaults()
        Settings.apply(PairingLink(server: "comms.church.org", passcode: "x", identity: "Op"), to: defaults)
        #expect(defaults.string(forKey: Settings.Key.serverURL) == "https://comms.church.org")
    }

    @Test("a code without a name is applied but not ready to connect")
    func missingIdentity() {
        let defaults = makeDefaults()
        let link = PairingLink(server: "10.0.0.5", passcode: "x")

        // Not ready — connecting anonymously would put an unnamed position on
        // comms that nobody can identify.
        #expect(Settings.apply(link, to: defaults) == false)
        #expect(defaults.string(forKey: Settings.Key.passcode) == "x")
    }

    @Test("an existing name survives a code that does not carry one")
    func keepsExistingIdentity() {
        let defaults = makeDefaults()
        defaults.set("Camera 3", forKey: Settings.Key.identity)

        #expect(Settings.apply(PairingLink(server: "10.0.0.5", passcode: "x"), to: defaults) == true)
        #expect(defaults.string(forKey: Settings.Key.identity) == "Camera 3")
    }

    @Test("a nonsense server is stored but not treated as ready")
    func unusableServer() {
        let defaults = makeDefaults()
        #expect(Settings.apply(PairingLink(server: "ftp://nope", passcode: "x", identity: "Op"), to: defaults) == false)
    }
}
