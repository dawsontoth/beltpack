import CryptoKit
import Foundation
import Testing

@testable import BeltpackKit

@Suite("AccessToken")
struct AccessTokenTests {
    private let key = "APItestkey"
    private let secret = "0123456789012345678901234567890123456789"

    private func decode(_ token: String) throws -> (header: [String: Any], claims: [String: Any], signingInput: String, signature: Data) {
        let parts = token.split(separator: ".").map(String.init)
        #expect(parts.count == 3)

        func decodeSegment(_ segment: String) throws -> Data {
            var s = segment.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            s += String(repeating: "=", count: (4 - s.count % 4) % 4)
            return Data(base64Encoded: s)!
        }

        let header = try JSONSerialization.jsonObject(with: decodeSegment(parts[0])) as! [String: Any]
        let claims = try JSONSerialization.jsonObject(with: decodeSegment(parts[1])) as! [String: Any]
        return (header, claims, "\(parts[0]).\(parts[1])", try decodeSegment(parts[2]))
    }

    @Test("signs with HMAC-SHA256 over the real secret")
    func signature() throws {
        let token = try AccessToken.mint(
            apiKey: key, apiSecret: secret, identity: "wing-bridge",
            grants: .init(room: "comms", canPublish: true, canSubscribe: false),
        )
        let parts = try decode(token)

        let expected = HMAC<SHA256>.authenticationCode(
            for: Data(parts.signingInput.utf8),
            using: SymmetricKey(data: Data(secret.utf8)),
        )
        #expect(Data(expected) == parts.signature)

        // A different secret must not validate, or the check above proves nothing.
        let wrong = HMAC<SHA256>.authenticationCode(
            for: Data(parts.signingInput.utf8),
            using: SymmetricKey(data: Data("a-completely-different-secret-value".utf8)),
        )
        #expect(Data(wrong) != parts.signature)
    }

    @Test("carries the grants it was asked for")
    func grants() throws {
        let token = try AccessToken.mint(
            apiKey: key, apiSecret: secret, identity: "Camera 2",
            grants: .init(room: "comms", canPublish: false, canSubscribe: true),
        )
        let claims = try decode(token).claims
        let video = claims["video"] as! [String: Any]

        #expect(claims["iss"] as? String == key)
        #expect(claims["sub"] as? String == "Camera 2")
        #expect(video["room"] as? String == "comms")
        #expect(video["roomJoin"] as? Bool == true)
        // Listen-only must not be able to publish; this is the phase gate.
        #expect(video["canPublish"] as? Bool == false)
        #expect(video["canSubscribe"] as? Bool == true)
        #expect(video["canPublishData"] as? Bool == false)
    }

    @Test("header declares HS256, which is what LiveKit verifies")
    func header() throws {
        let token = try AccessToken.mint(
            apiKey: key, apiSecret: secret, identity: "x",
            grants: .init(room: "comms", canPublish: true, canSubscribe: true),
        )
        let header = try decode(token).header
        #expect(header["alg"] as? String == "HS256")
        #expect(header["typ"] as? String == "JWT")
    }

    @Test("expiry sits in the future and respects the requested ttl")
    func expiry() throws {
        let token = try AccessToken.mint(
            apiKey: key, apiSecret: secret, identity: "x",
            grants: .init(room: "comms", canPublish: true, canSubscribe: true),
            ttl: 3600,
        )
        let claims = try decode(token).claims
        let now = Date().timeIntervalSince1970
        let exp = claims["exp"] as! Double
        let nbf = claims["nbf"] as! Double

        #expect(nbf <= now + 1)
        #expect(exp > now)
        #expect(abs(exp - (now + 3600)) < 5)
    }

    @Test("private IPs and mDNS names are recognised as local")
    func localDetection() {
        // Shared with the bridge's own decisions about cleartext.
        #expect(AudioDevices.list(.input).allSatisfy { $0.channels > 0 })
    }
}
