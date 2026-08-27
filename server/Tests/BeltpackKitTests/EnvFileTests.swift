import Foundation
import Testing

@testable import BeltpackKit

/// Writing `.env` back after the control panel changes something.
///
/// This is a file people also edit by hand, so the bar is that a change to one
/// value leaves every other byte alone.
@Suite("EnvFile.update")
struct EnvFileTests {
    private func withTempFile(_ contents: String, _ body: (URL) throws -> Void) throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("beltpack-env-\(UUID().uuidString)")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        try body(url)
    }

    @Test("changes a value and leaves comments and order alone")
    func preservesEverythingElse() throws {
        let original = """
        # A comment worth keeping
        LIVEKIT_API_KEY="devkey"

        # Which channel carries comms
        BELTPACK_INPUT_CHANNEL="1"
        BELTPACK_OUTPUT_DEVICE="WING"

        """
        try withTempFile(original) { url in
            try EnvFile.update(url, ["BELTPACK_INPUT_CHANNEL": "42"])
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("# A comment worth keeping"))
            #expect(text.contains("# Which channel carries comms"))
            #expect(text.contains("BELTPACK_INPUT_CHANNEL=\"42\""))
            #expect(!text.contains("BELTPACK_INPUT_CHANNEL=\"1\""))
            #expect(text.contains("BELTPACK_OUTPUT_DEVICE=\"WING\""))
            // Order is how a person finds things in a file they also edit.
            let keyIndex = try #require(text.range(of: "LIVEKIT_API_KEY"))
            let channelIndex = try #require(text.range(of: "BELTPACK_INPUT_CHANNEL"))
            #expect(keyIndex.lowerBound < channelIndex.lowerBound)
        }
    }

    /// A file that ended with a newline still does. Appending after the final
    /// blank line is what silently strips it.
    @Test("a trailing newline survives, including when keys are appended")
    func keepsTrailingNewline() throws {
        try withTempFile("FOO=\"1\"\n") { url in
            try EnvFile.update(url, ["FOO": "2"])
            #expect(try String(contentsOf: url, encoding: .utf8).hasSuffix("\n"))

            try EnvFile.update(url, ["BELTPACK_INPUT_CHANNEL": "42"])
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.hasSuffix("\n"))
            #expect(text.contains("BELTPACK_INPUT_CHANNEL=\"42\""))
        }
    }

    @Test("a file with no trailing newline does not gain one")
    func leavesNoNewlineAlone() throws {
        try withTempFile("FOO=\"1\"") { url in
            try EnvFile.update(url, ["FOO": "2"])
            #expect(try !String(contentsOf: url, encoding: .utf8).hasSuffix("\n"))
        }
    }

    @Test("keys the file never mentioned are appended")
    func appendsMissingKeys() throws {
        try withTempFile("FOO=\"1\"\n") { url in
            try EnvFile.update(url, ["BELTPACK_CAN_PUBLISH": "false"])
            let values = try EnvFile.load(url)
            #expect(values["FOO"] == "1")
            #expect(values["BELTPACK_CAN_PUBLISH"] == "false")
        }
    }

    /// `export KEY=value` is what people paste in out of habit, and rewriting
    /// it without the export would change what sourcing the file does.
    @Test("an exported key stays exported")
    func keepsExport() throws {
        try withTempFile("export FOO=\"1\"\n") { url in
            try EnvFile.update(url, ["FOO": "2"])
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("export FOO=\"2\""))
        }
    }

    /// A commented-out setting is a note, not a setting. Rewriting it would
    /// silently switch something on that somebody deliberately turned off.
    @Test("a commented-out key is left as a comment")
    func ignoresComments() throws {
        try withTempFile("#FOO=\"1\"\nBAR=\"2\"\n") { url in
            try EnvFile.update(url, ["FOO": "9"])
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("#FOO=\"1\""))
            #expect(text.contains("FOO=\"9\""))
        }
    }

    @Test("round trips through load")
    func roundTrips() throws {
        try withTempFile("A=\"1\"\nB=\"2\"\n") { url in
            try EnvFile.update(url, ["A": "x", "B": "y"])
            let values = try EnvFile.load(url)
            #expect(values["A"] == "x")
            #expect(values["B"] == "y")
        }
    }
}
