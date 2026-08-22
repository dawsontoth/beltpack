import Foundation
import Testing

@testable import BeltpackKit

@Suite("PairingLink")
struct PairingLinkTests {
    @Test("round-trips through the app scheme")
    func appRoundTrip() throws {
        let link = PairingLink(server: "http://172.16.1.41:7883", passcode: "9qmbutqe38", identity: "Camera 2")
        let url = try #require(link.appURL)
        #expect(url.scheme == "beltpack")
        #expect(url.host == "join")

        let parsed = try #require(PairingLink.parse(url))
        #expect(parsed == link)
    }

    @Test("round-trips through the web form")
    func webRoundTrip() throws {
        let link = PairingLink(server: "https://comms.church.org", passcode: "hunter2")
        let url = try #require(link.webURL)
        #expect(url.absoluteString.hasPrefix("https://comms.church.org/?"))

        let parsed = try #require(PairingLink.parse(url))
        #expect(parsed.server == link.server)
        #expect(parsed.passcode == link.passcode)
        #expect(parsed.identity == nil)
    }

    @Test("percent-encodes characters that would otherwise break the query")
    func encoding() throws {
        // A generated passcode is alphanumeric, but a hand-set one might not be.
        let link = PairingLink(server: "http://10.0.0.5:7883", passcode: "a b&c=d?e#f")
        let url = try #require(link.appURL)
        #expect(!url.absoluteString.contains("a b&c"))

        let parsed = try #require(PairingLink.parse(url))
        #expect(parsed.passcode == "a b&c=d?e#f")
    }

    @Test("identity is optional and omitted when empty")
    func optionalIdentity() throws {
        let link = PairingLink(server: "http://10.0.0.5:7883", passcode: "x", identity: "")
        let url = try #require(link.appURL)
        #expect(!url.absoluteString.contains("identity"))
        #expect(PairingLink.parse(url)?.identity == nil)
    }

    @Test("refuses links that are not pairing links")
    func rejectsOthers() {
        #expect(PairingLink.parse(URL(string: "beltpack://something-else?server=a&passcode=b")!) == nil)
        #expect(PairingLink.parse(URL(string: "https://example.org/")!) == nil)
    }

    @Test("refuses a half-configured link rather than partially applying it")
    func rejectsIncomplete() {
        // Applying server without passcode would leave a volunteer staring at
        // a form that looks filled in but cannot connect.
        #expect(PairingLink.parse(URL(string: "beltpack://join?server=http://10.0.0.5")!) == nil)
        #expect(PairingLink.parse(URL(string: "beltpack://join?passcode=x")!) == nil)
        #expect(PairingLink.parse(URL(string: "beltpack://join?server=&passcode=x")!) == nil)
    }
}
