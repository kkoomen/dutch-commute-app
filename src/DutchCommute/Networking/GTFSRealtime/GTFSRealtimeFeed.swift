import Foundation

/// One GTFS-Realtime feed: a `.pb` endpoint. Additional providers/feeds can
/// be added by configuring more feeds; the UI never sees this type.
struct GTFSRealtimeFeed: Equatable {
    let id: String
    let url: URL
    /// Feed header timestamps older than this are considered stale.
    let maxAge: TimeInterval
    let providesTripUpdates: Bool
    let providesAlerts: Bool
    let providesVehiclePositions: Bool

    init(
        id: String,
        url: URL,
        maxAge: TimeInterval = 180,
        providesTripUpdates: Bool = true,
        providesAlerts: Bool = true,
        providesVehiclePositions: Bool = false
    ) {
        self.id = id
        self.url = url
        self.maxAge = maxAge
        self.providesTripUpdates = providesTripUpdates
        self.providesAlerts = providesAlerts
        self.providesVehiclePositions = providesVehiclePositions
    }
}
