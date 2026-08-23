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

        #expect(Settings.apply(link, to: defaults) == .ready)
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
        // comms that nobody can identify. The server and passcode are still
        // stored, so the app has exactly one thing left to ask for.
        #expect(Settings.apply(link, to: defaults) == .needsName)
        #expect(defaults.string(forKey: Settings.Key.passcode) == "x")
        #expect(defaults.string(forKey: Settings.Key.serverURL)?.isEmpty == false)
    }

    @Test("an existing name survives a code that does not carry one")
    func keepsExistingIdentity() {
        let defaults = makeDefaults()
        defaults.set("Camera 3", forKey: Settings.Key.identity)

        #expect(Settings.apply(PairingLink(server: "10.0.0.5", passcode: "x"), to: defaults) == .ready)
        #expect(defaults.string(forKey: Settings.Key.identity) == "Camera 3")
    }

    /// The two ways a code can fail need opposite things from whoever
    /// scanned it, so they must not collapse into one answer: a missing name
    /// is worth asking about, a broken server is not.
    @Test("a nonsense server is unusable rather than merely unnamed")
    func unusableServer() {
        let defaults = makeDefaults()
        let outcome = Settings.apply(PairingLink(server: "ftp://nope", passcode: "x", identity: "Op"), to: defaults)
        #expect(outcome == .unusable)
        #expect(outcome != .needsName)
    }

    @Test("a nonsense server stays unusable even with no name to fall back on")
    func unusableServerWithoutName() {
        let defaults = makeDefaults()
        #expect(Settings.apply(PairingLink(server: "ftp://nope", passcode: "x"), to: defaults) == .unusable)
    }
}

/// The gain sliders work in whole decibels while the stored value stays linear.
@Suite("Gain")
struct GainTests {
    @Test("unity is exactly 0 dB, and round-trips")
    func unity() {
        #expect(Settings.decibels(fromGain: 1) == 0)
        #expect(Settings.gain(fromDecibels: 0) == 1)
    }

    @Test("the top of the decibel range reaches the cap without exceeding it")
    func topOfRange() {
        let top = Settings.gain(fromDecibels: Settings.decibelRange.upperBound)
        // +6 dB is 1.995 rather than exactly 2. What matters is that the
        // slider gets within a whisker of the cap and never past it — a
        // multiplier above the cap would be a limit that does not hold.
        #expect(top <= Settings.gainRange.upperBound)
        #expect(top > Settings.gainRange.upperBound - 0.01)
    }

    @Test("whole decibels round-trip without drifting")
    func roundTrip() {
        for decibels in stride(from: -24.0, through: 6.0, by: 1) {
            let gain = Settings.gain(fromDecibels: decibels)
            #expect(abs(Settings.decibels(fromGain: gain) - decibels) < 0.001)
        }
    }

    @Test("silence reads as the bottom of the range rather than negative infinity")
    func silence() {
        #expect(Settings.decibels(fromGain: 0) == Settings.decibelRange.lowerBound)
    }

    @Test("values outside the range are clamped rather than accepted")
    func clamping() {
        #expect(Settings.gain(fromDecibels: 60) <= Settings.gainRange.upperBound)
        #expect(Settings.gain(fromDecibels: -200) >= Settings.gainRange.lowerBound)
        #expect(Settings.decibels(fromGain: 100) == Settings.decibelRange.upperBound)
    }
}
