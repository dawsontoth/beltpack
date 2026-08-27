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

    /// Gates the management page. Deliberately separate from the join
    /// passcode: that one is printed on QR codes and handed to volunteers,
    /// while this one can re-patch what the console is capturing.
    public let adminPasscode: String?
    public let adminPort: UInt16

    /// Where the summed phone audio goes back out. Only used when
    /// `subscribes` is true; route it to the WING channel feeding Bus 1.
    public let outputDeviceHint: String?

    /// Which channel of a multichannel interface carries comms, 1-based to
    /// match what the console prints. Nil means "whatever the device hands us
    /// first", which is right for an ordinary two-channel interface and wrong
    /// for a 48-channel console where the first channels are already in use.
    public let inputChannel: Int?
    public let outputChannel: Int?

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

        // A channel number is 1-based and must be a real one; 0 or a stray
        // non-number means the same as not asking, rather than silently
        // selecting something adjacent.
        func channel(_ raw: String?) -> Int? {
            guard let raw, let value = Int(raw.trimmingCharacters(in: .whitespaces)), value >= 1 else { return nil }
            return value
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
            adminPasscode: env["BELTPACK_ADMIN_PASSCODE"].flatMap { $0.isEmpty ? nil : $0 },
            adminPort: UInt16(env["BELTPACK_ADMIN_PORT"] ?? "") ?? 7884,
            outputDeviceHint: env["BELTPACK_OUTPUT_DEVICE"].flatMap { $0.isEmpty ? nil : $0 },
            inputChannel: channel(env["BELTPACK_INPUT_CHANNEL"]),
            outputChannel: channel(env["BELTPACK_OUTPUT_CHANNEL"]),
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
