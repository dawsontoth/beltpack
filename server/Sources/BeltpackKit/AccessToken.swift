import CryptoKit
import Foundation

/// Mints a LiveKit access token (HS256 JWT).
///
/// The bridge runs on the same machine as the LiveKit server and already holds
/// the API secret, so it signs its own token rather than round-tripping through
/// the token service the phones use.
public enum AccessToken {
    public struct Grants {
        public var room: String
        public var canPublish: Bool
        public var canSubscribe: Bool
        public var canPublishData: Bool = false

        public init(room: String, canPublish: Bool, canSubscribe: Bool, canPublishData: Bool = false) {
            self.room = room
            self.canPublish = canPublish
            self.canSubscribe = canSubscribe
            self.canPublishData = canPublishData
        }
    }

    public static func mint(
        apiKey: String,
        apiSecret: String,
        identity: String,
        grants: Grants,
        ttl: TimeInterval = 6 * 60 * 60,
    ) throws -> String {
        let now = Date()

        let header: [String: Any] = ["alg": "HS256", "typ": "JWT"]
        let payload: [String: Any] = [
            "iss": apiKey,
            "sub": identity,
            "name": identity,
            "nbf": Int(now.timeIntervalSince1970),
            "exp": Int(now.addingTimeInterval(ttl).timeIntervalSince1970),
            "video": [
                "room": grants.room,
                "roomJoin": true,
                "canPublish": grants.canPublish,
                "canSubscribe": grants.canSubscribe,
                "canPublishData": grants.canPublishData,
            ],
        ]

        let signingInput = try encode(header) + "." + encode(payload)
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(signingInput.utf8),
            using: SymmetricKey(data: Data(apiSecret.utf8)),
        )

        return signingInput + "." + base64URL(Data(signature))
    }

    private static func encode(_ object: [String: Any]) throws -> String {
        // .sortedKeys keeps the output stable, which makes tokens diffable in logs.
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return base64URL(data)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
