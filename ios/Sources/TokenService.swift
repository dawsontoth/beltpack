import Foundation

/// Trades the shared passcode for a short-lived LiveKit token.
///
/// The app never holds the API secret — only the server does.
enum TokenService {
    struct Credentials: Decodable {
        let url: String
        let token: String
    }

    static func fetch(serverURL: String, identity: String, passcode: String) async throws -> Credentials {
        guard var components = URLComponents(string: serverURL) else {
            throw TokenError.badServerURL(serverURL)
        }
        components.path = "/token"
        components.queryItems = [URLQueryItem(name: "identity", value: identity)]

        guard let url = components.url else {
            throw TokenError.badServerURL(serverURL)
        }

        var request = URLRequest(url: url)
        // The passcode rides in a header, never the query string.
        request.setValue(passcode, forHTTPHeaderField: "X-Beltpack-Passcode")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TokenError.unreachable
        }
        guard http.statusCode != 401 else {
            throw TokenError.wrongPasscode
        }
        guard http.statusCode == 200 else {
            throw TokenError.server(http.statusCode)
        }

        return try JSONDecoder().decode(Credentials.self, from: data)
    }
}

enum TokenError: LocalizedError {
    case badServerURL(String)
    case unreachable
    case wrongPasscode
    case server(Int)

    var errorDescription: String? {
        switch self {
        case let .badServerURL(value): "\"\(value)\" isn't a valid server address."
        case .unreachable: "Can't reach the comms server. Check you're on the comms Wi-Fi."
        case .wrongPasscode: "That passcode was rejected."
        case let .server(code): "Comms server returned \(code)."
        }
    }
}
