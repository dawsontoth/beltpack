import Foundation

/// A pairing link, so nobody types a server address or a passcode by hand.
///
/// Two forms, because one QR code cannot serve both platforms:
///
///   beltpack://join?server=…&passcode=…   opens the native iOS app
///   https://host/?server=…&passcode=…     opens the web client, for Android
///
/// The passcode travels inside the code, so treat a printed one as a
/// credential: anyone who photographs it is on comms.
public struct PairingLink: Sendable, Equatable {
    public static let scheme = "beltpack"
    public static let host = "join"

    public var server: String
    public var passcode: String
    public var identity: String?

    public init(server: String, passcode: String, identity: String? = nil) {
        self.server = server
        self.passcode = passcode
        self.identity = identity
    }

    /// The `beltpack://` form the iOS app registers.
    public var appURL: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.queryItems = queryItems
        return components.url
    }

    /// The web form, for Android and booth laptops. Built from the server
    /// address itself, since the PWA is served from the same origin.
    public var webURL: URL? {
        guard var components = URLComponents(string: server) else { return nil }
        components.path = "/"
        components.queryItems = queryItems
        return components.url
    }

    private var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "server", value: server),
            URLQueryItem(name: "passcode", value: passcode),
        ]
        if let identity, !identity.isEmpty {
            items.append(URLQueryItem(name: "identity", value: identity))
        }
        return items
    }

    /// Parses either form. Returns nil when the link is not a pairing link or
    /// is missing what it needs — never a half-configured result.
    public static func parse(_ url: URL) -> PairingLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        if url.scheme?.lowercased() == scheme {
            guard url.host?.lowercased() == host else { return nil }
        }

        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }

        guard let server = value("server"), let passcode = value("passcode") else { return nil }
        return PairingLink(server: server, passcode: passcode, identity: value("identity"))
    }
}
