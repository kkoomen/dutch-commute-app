import Foundation

/// A disruption or service alert in app-level terms (from GTFS-Realtime
/// Alert entities).
struct ServiceAlert: Identifiable, Equatable {
    let id: String
    let header: String
    let summary: String
    /// GTFS cause name, e.g. "MAINTENANCE" or "WEATHER".
    let cause: String
    /// GTFS effect name, e.g. "DETOUR" or "SIGNIFICANT_DELAYS".
    let effect: String
    let startDate: Date?
    let endDate: Date?
    /// Affected GTFS route ids; empty = network-wide.
    let affectedRouteIDs: [String]
    /// Affected GTFS stop ids; empty = all stops.
    let affectedStopIDs: [String]
}
