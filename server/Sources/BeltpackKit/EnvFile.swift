import Foundation

/// Reads a `.env` file.
///
/// The CLI gets its configuration from the process environment, because
/// `run.sh` sources `.env` before exec'ing it. A GUI app launched from Finder
/// has no such environment, so it reads the same file directly — one source of
/// truth rather than two ways to configure the same thing.
public enum EnvFile {
    public static func load(_ url: URL) throws -> [String: String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var values: [String: String] = [:]

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            // Tolerate `export KEY=value`, which people paste in out of habit.
            var body = line
            if body.hasPrefix("export ") { body = String(body.dropFirst(7)) }

            guard let equals = body.firstIndex(of: "=") else { continue }
            let key = String(body[body.startIndex ..< equals]).trimmingCharacters(in: .whitespaces)
            var value = String(body[body.index(after: equals)...]).trimmingCharacters(in: .whitespaces)

            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'"))
            {
                value = String(value.dropFirst().dropLast())
            }

            guard !key.isEmpty else { continue }
            values[key] = value
        }

        return values
    }

    /// Rewrites keys in place, leaving every other line — comments, ordering,
    /// spacing — exactly as it was. `.env` is a file people read and edit by
    /// hand, so a round trip through a dictionary would be a poor trade for
    /// changing one value.
    ///
    /// Keys not already present are appended. The write goes to a sibling file
    /// and is moved into place, so an interrupted save cannot leave a booth
    /// Mac holding half a config.
    public static func update(_ url: URL, _ values: [String: String]) throws {
        guard !values.isEmpty else { return }
        let text = try String(contentsOf: url, encoding: .utf8)
        var remaining = values
        var lines: [String] = []

        // Split off the final newline and put it back at the end, rather than
        // carrying it along as an empty last line — appending after that empty
        // line is what leaves a file with no newline at the end of it.
        let endsWithNewline = text.hasSuffix("\n")
        let body = endsWithNewline ? String(text.dropLast()) : text

        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            var body = line.trimmingCharacters(in: .whitespaces)
            let exported = body.hasPrefix("export ")
            if exported { body = String(body.dropFirst(7)) }

            guard !body.isEmpty, !body.hasPrefix("#"),
                  let equals = body.firstIndex(of: "="),
                  case let key = String(body[body.startIndex ..< equals]).trimmingCharacters(in: .whitespaces),
                  let replacement = remaining.removeValue(forKey: key)
            else {
                lines.append(line)
                continue
            }

            lines.append("\(exported ? "export " : "")\(key)=\"\(replacement)\"")
        }

        // Anything the file did not already mention.
        if !remaining.isEmpty {
            if lines.last?.isEmpty == false { lines.append("") }
            for key in remaining.keys.sorted() {
                lines.append("\(key)=\"\(remaining[key]!)\"")
            }
        }

        let scratch = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).new")
        let output = lines.joined(separator: "\n") + (endsWithNewline ? "\n" : "")
        try output.write(to: scratch, atomically: false, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: scratch)
    }
}
