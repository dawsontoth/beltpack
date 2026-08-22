import Foundation

/// Everything the bridge needs, read from the environment.
///
/// Nothing is hard-coded and nothing is committed: `make run` loads `.env`
/// from the repo root before exec'ing the binary.
public struct Config: Sendable {
    public let livekitURL: String
    public let apiKey: String
    public let apiSecret: String
    public let room: String
    public let identity: String

    /// Substring matched against Core Audio input device names, e.g. "WING".
    public let inputDeviceHint: String

    /// Phase 2. When true the bridge also subscribes, so it can sum the phone
    /// mics back into the console. Listen-only builds leave this false.
    public let subscribes: Bool

    /// What a phone should be pointed at — the address serving the token
    /// endpoint. Only needed to build pairing codes, so it is optional.
    public let clientURL: String?

    /// The shared join passcode, carried inside a pairing code.
    public let passcode: String?

    /// Where the summed phone audio goes back out. Only used when
    /// `subscribes` is true; route it to the WING channel feeding Bus 1.
    public let outputDeviceHint: String?

    public static func fromEnvironment() throws -> Config {
        try from(ProcessInfo.processInfo.environment)
    }

    /// Same validation, reading a `.env` file instead of the environment.
    public static func fromEnvFile(_ url: URL) throws -> Config {
        try from(EnvFile.load(url))
    }

    public static func from(_ env: [String: String]) throws -> Config {

        func required(_ key: String) throws -> String {
            guard let value = env[key], !value.isEmpty else {
                throw ConfigError.missing(key)
            }
            return value
        }

        let secret = try required("LIVEKIT_API_SECRET")
        guard secret.count >= 32 else {
            throw ConfigError.secretTooShort(secret.count)
        }

        return Config(
            livekitURL: env["LIVEKIT_URL"] ?? "ws://127.0.0.1:7880",
            apiKey: try required("LIVEKIT_API_KEY"),
            apiSecret: secret,
            room: env["BELTPACK_ROOM"] ?? "comms",
            identity: env["BELTPACK_IDENTITY"] ?? "wing-bridge",
            inputDeviceHint: try required("BELTPACK_INPUT_DEVICE"),
            subscribes: (env["BELTPACK_SUBSCRIBE"] ?? "false") == "true",
            clientURL: env["BELTPACK_CLIENT_URL"].flatMap { $0.isEmpty ? nil : $0 },
            passcode: env["BELTPACK_PASSCODE"].flatMap { $0.isEmpty ? nil : $0 },
            outputDeviceHint: env["BELTPACK_OUTPUT_DEVICE"].flatMap { $0.isEmpty ? nil : $0 },
        )
    }
}

public enum ConfigError: LocalizedError {
    case missing(String)
    case secretTooShort(Int)

    public var errorDescription: String? {
        switch self {
        case let .missing(key):
            "Set \(key). Copy .env.example to .env and fill it in."
        case let .secretTooShort(count):
            "LIVEKIT_API_SECRET is \(count) characters; LiveKit requires at least 32."
        }
    }
}
