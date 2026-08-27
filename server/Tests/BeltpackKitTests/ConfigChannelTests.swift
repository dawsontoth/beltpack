import Foundation
import Testing

@testable import BeltpackKit

/// Choosing which channel of a console carries comms.
///
/// The channel map itself needs a multichannel device to mean anything, so
/// what is pinned here is the part that decides whether one is asked for at
/// all — where a wrong answer routes a service to silence.
@Suite("Config channels")
struct ConfigChannelTests {
    private func base(_ extra: [String: String] = [:]) -> [String: String] {
        var env = [
            "LIVEKIT_API_KEY": "devkey",
            "LIVEKIT_API_SECRET": String(repeating: "s", count: 32),
            "BELTPACK_INPUT_DEVICE": "WING",
        ]
        for (k, v) in extra { env[k] = v }
        return env
    }

    @Test("a channel number is carried through as written")
    func carriesChannels() throws {
        let config = try Config.from(base([
            "BELTPACK_INPUT_CHANNEL": "42",
            "BELTPACK_OUTPUT_CHANNEL": "42",
        ]))
        #expect(config.inputChannel == 42)
        #expect(config.outputChannel == 42)
    }

    /// Absent means "take what the device offers first", which is correct for
    /// an ordinary two-channel interface.
    @Test("absent means no channel map at all")
    func absentMeansDefault() throws {
        let config = try Config.from(base())
        #expect(config.inputChannel == nil)
        #expect(config.outputChannel == nil)
    }

    @Test("blank is the same as absent, since that is what .env.example ships")
    func blankMeansDefault() throws {
        let config = try Config.from(base([
            "BELTPACK_INPUT_CHANNEL": "",
            "BELTPACK_OUTPUT_CHANNEL": "  ",
        ]))
        #expect(config.inputChannel == nil)
        #expect(config.outputChannel == nil)
    }

    /// Channels are 1-based because that is how a console prints them. Zero is
    /// what someone writes when they think otherwise, and quietly reading it as
    /// channel 1 would send comms somewhere plausible and wrong.
    @Test("zero and negatives are refused rather than reinterpreted")
    func rejectsOutOfRange() throws {
        let config = try Config.from(base([
            "BELTPACK_INPUT_CHANNEL": "0",
            "BELTPACK_OUTPUT_CHANNEL": "-3",
        ]))
        #expect(config.inputChannel == nil)
        #expect(config.outputChannel == nil)
    }

    @Test("nonsense is refused rather than guessed at")
    func rejectsNonsense() throws {
        let config = try Config.from(base(["BELTPACK_INPUT_CHANNEL": "forty-two"]))
        #expect(config.inputChannel == nil)
    }

    @Test("only one side needs asking for")
    func inputWithoutOutput() throws {
        let config = try Config.from(base(["BELTPACK_INPUT_CHANNEL": "42"]))
        #expect(config.inputChannel == 42)
        #expect(config.outputChannel == nil)
    }
}
