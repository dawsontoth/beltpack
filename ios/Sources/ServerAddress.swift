import Foundation

/// Turns what someone actually types into a usable server URL.
///
/// Volunteers set this once, on a phone, in a dark booth. Demanding a
/// well-formed URL is a bad trade when the intent is nearly always obvious:
///
///     172.16.1.41            -> http://172.16.1.41:7883
///     172.16.1.41:7883       -> http://172.16.1.41:7883
///     comms.church.org       -> https://comms.church.org
///     HTTPS://Comms.Church.Org/  -> https://comms.church.org
///
/// The scheme is inferred rather than assumed: a private or link-local
/// address is a bench setup with no certificate, so it gets http and the
/// default port. Anything else is a real hostname behind Caddy, so it gets
/// https on 443. An explicit scheme or port always wins.
enum ServerAddress {
    static let defaultLocalPort = 7883

    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Drop any path someone pasted along with the host — we always talk
        // to /token, and a stray /token in the setting would double up.
        var scheme: String?
        if let range = text.range(of: "://") {
            scheme = String(text[text.startIndex ..< range.lowerBound]).lowercased()
            text = String(text[range.upperBound...])
        }
        if let slash = text.firstIndex(of: "/") {
            text = String(text[text.startIndex ..< slash])
        }
        guard !text.isEmpty else { return nil }

        // Split host:port, being careful not to mangle a bracketed IPv6 host.
        var host = text
        var port: Int?
        if !text.hasPrefix("[") {
            let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2, let parsed = Int(parts[1]), (1 ... 65535).contains(parsed) {
                host = String(parts[0])
                port = parsed
            } else if parts.count == 2 {
                return nil // "host:notaport"
            }
        }

        host = host.lowercased()
        guard !host.isEmpty, !host.contains(" ") else { return nil }

        let local = isLocal(host)
        let resolvedScheme = scheme ?? (local ? "http" : "https")
        guard resolvedScheme == "http" || resolvedScheme == "https" else { return nil }

        var components = URLComponents()
        components.scheme = resolvedScheme
        components.host = host
        // Only default the port for a bench setup. A real hostname is behind
        // Caddy on 443, where naming the port would be wrong.
        if let port {
            components.port = port
        } else if local, resolvedScheme == "http" {
            components.port = defaultLocalPort
        }

        return components.url
    }

    /// Private, loopback, link-local, or mDNS — anything that cannot have a
    /// public certificate.
    static func isLocal(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") { return true }

        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0 ... 255).contains($0) }) else { return false }

        switch (octets[0], octets[1]) {
        case (10, _): return true
        case (127, _): return true
        case (192, 168): return true
        case (169, 254): return true
        case (172, 16 ... 31): return true
        default: return false
        }
    }
}
