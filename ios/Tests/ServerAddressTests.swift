import Testing
@testable import Beltpack

@Suite("ServerAddress")
struct ServerAddressTests {
    private func normalized(_ input: String) -> String? {
        ServerAddress.normalize(input)?.absoluteString
    }

    @Test("a bare private IP becomes http on the default port")
    func bareprivateIP() {
        #expect(normalized("172.16.1.41") == "http://172.16.1.41:7883")
        #expect(normalized("192.168.0.10") == "http://192.168.0.10:7883")
        #expect(normalized("10.0.0.5") == "http://10.0.0.5:7883")
    }

    @Test("an explicit port is respected")
    func explicitPort() {
        #expect(normalized("172.16.1.41:9000") == "http://172.16.1.41:9000")
    }

    @Test("a real hostname becomes https with no port")
    func publicHostname() {
        #expect(normalized("comms.church.org") == "https://comms.church.org")
    }

    @Test("an explicit scheme always wins")
    func explicitScheme() {
        #expect(normalized("http://comms.church.org") == "http://comms.church.org")
        #expect(normalized("https://172.16.1.41") == "https://172.16.1.41")
    }

    @Test("whitespace, case, and trailing slashes are forgiven")
    func messyInput() {
        #expect(normalized("  HTTPS://Comms.Church.Org/  ") == "https://comms.church.org")
        #expect(normalized("172.16.1.41/") == "http://172.16.1.41:7883")
    }

    @Test("a pasted path is discarded so /token is not doubled up")
    func pastedPath() {
        #expect(normalized("http://172.16.1.41:7883/token") == "http://172.16.1.41:7883")
    }

    @Test(".local and localhost count as local")
    func mdnsAndLoopback() {
        #expect(normalized("comms.local") == "http://comms.local:7883")
        #expect(normalized("localhost") == "http://localhost:7883")
    }

    @Test("public-looking IPs are not treated as local")
    func publicIP() {
        // 172.32 is outside the private 172.16–31 range; a classic off-by-one.
        #expect(normalized("172.32.0.1") == "https://172.32.0.1")
        #expect(normalized("8.8.8.8") == "https://8.8.8.8")
    }

    @Test("nonsense is rejected rather than guessed at")
    func rejected() {
        #expect(ServerAddress.normalize("") == nil)
        #expect(ServerAddress.normalize("   ") == nil)
        #expect(ServerAddress.normalize("172.16.1.41:notaport") == nil)
        #expect(ServerAddress.normalize("ftp://172.16.1.41") == nil)
    }
}
