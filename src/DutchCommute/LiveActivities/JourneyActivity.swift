import ActivityKit
import Foundation

/// Immutable identity of a journey Live Activity.
struct JourneyActivityAttributes: ActivityAttributes {
    /// Dynamic, updatable state.
    public struct ContentState: Codable, Hashable {
        /// Route/train name shown on the activity, e.g. "IC 1234"
        /// (dynamic — the planned placeholder is replaced once the live
        /// leg info arrives, because ActivityKit attributes are immutable).
        var routeName: String
        /// The leg's departure and destination stations, in travel
        /// direction (dynamic — the outbound and return legs differ, and
        /// ActivityKit attributes are immutable).
        var fromName: String
        var toName: String
        /// Departure track, e.g. "4"; nil when the API didn't provide one.
        var track: String?
        /// Shown departure time (actual when known, else planned).
        var departureTime: Date
        /// Status text, e.g. "On time", "+5 min", "Cancelled".
        var status: String
        var isCancelled: Bool
        var lastUpdate: Date?
        /// True when the last refresh failed and the shown data may be old.
        var isStale: Bool
    }

    let journeyID: UUID
    let routeName: String
    let fromName: String
    let toName: String
    let destination: String
    let scheduledDeparture: Date
}
