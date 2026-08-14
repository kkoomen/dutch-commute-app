import Foundation

/// Reads the NS API key from the bundled `.env` file
/// (copied from `src/.env` into the app bundle as a resource).
/// No build scripts involved — the key lives only in the git-ignored `src/.env`.
enum APIKey {
    static let ns: String = {
        guard let url = Bundle.main.url(forResource: ".env", withExtension: nil),
              let content = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return Self.parse(content)
    }()

    /// Parses `NS_API_KEY=` from dotenv-style content: `KEY="value"` or `KEY=value`.
    static func parse(_ content: String) -> String {
        for rawLine in content.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0] == "NS_API_KEY" else { continue }
            return parts[1]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return ""
    }
}
