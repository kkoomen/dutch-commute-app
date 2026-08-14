import Foundation

/// A train station as the user sees it (NS station code + display name).
struct Station: Codable, Hashable, Identifiable {
    let code: String
    let name: String

    var id: String { code }
}
