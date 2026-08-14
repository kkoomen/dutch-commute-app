import Foundation

/// A mode of public transport, shared by the NS API and GTFS providers.
enum TransportMode: Equatable {
    case train, bus, metro, tram, ferry

    /// Display name, e.g. "Train".
    var label: String {
        switch self {
        case .train: String(localized: "Train")
        case .bus: String(localized: "Bus")
        case .metro: String(localized: "Metro")
        case .tram: String(localized: "Tram")
        case .ferry: String(localized: "Ferry")
        }
    }

    /// SF Symbol for the mode.
    var icon: String {
        switch self {
        case .train: "train.side.front.car"
        case .bus: "bus.fill"
        case .metro: "tram.fill.tunnel"
        case .tram: "tram.fill"
        case .ferry: "ferry.fill"
        }
    }
}

/// A train station as the user sees it (NS station code + display name).
struct Station: Codable, Hashable, Identifiable {
    let code: String
    let name: String

    var id: String { code }
}

/// A selectable stop from either the NS API (train) or static GTFS
/// (bus/metro/tram). The picker presents these; journeys store the plain
/// `Station` (code = the choice id).
struct StationChoice: Identifiable, Equatable {
    let id: String
    let name: String
    let mode: TransportMode
}