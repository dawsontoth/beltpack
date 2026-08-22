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
}
