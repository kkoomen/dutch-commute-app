import ActivityKit
import Foundation

/// Immutable identity of a journey Live Activity.
struct JourneyActivityAttributes: ActivityAttributes {
    /// Dynamic, updatable state.
    public struct ContentState: Codable, Hashable {
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
