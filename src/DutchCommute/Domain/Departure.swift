import Foundation

/// A mode of public transport, shared by the NS API and GTFS providers.
enum TransportMode: Equatable {
    case train, bus, metro, tram, ferry
}

/// A single public-transport departure (train, bus, tram, metro) in
/// app-level terms. Both the NS API and GTFS-Realtime providers produce
/// this type; views and widgets never see the underlying API types.
struct Departure: Identifiable, Equatable {
    /// Stable identity across refreshes: provider + trip + stop.
    let id: String
    let mode: TransportMode
    /// Display name, e.g. "IC 1234", "Bus 38", "Tram 9".
    let routeName: String
    let destination: String
    let stopID: String
    let stopName: String
    let scheduledDeparture: Date
    /// Live departure time when known (delay applied); nil = not updated.
    let actualDeparture: Date?
    let status: TrainStatus
    /// GTFS trip id when the departure came from a GTFS feed.
    let tripID: String?
}
