import Foundation

/// App-facing abstraction over live transit data. Views and the widget
/// depend only on this protocol and the domain types (`Departure`,
/// `ServiceAlert`); an NS-API or any other GTFS provider can be added as a
/// new implementation without touching the UI.
protocol TransitDataService {
    /// Upcoming departures from a stop, soonest first.
    func upcomingDepartures(fromStop stopID: String, at date: Date, limit: Int) async -> [Departure]

    /// Alerts active around `date`.
    func activeAlerts(at date: Date) async -> [ServiceAlert]
}

/// GTFS-backed implementation: static GTFS schedules joined with live
/// GTFS-Realtime feeds.
struct GTFSTransitDataService: TransitDataService {
    let realtime: RealtimeUpdateService

    func upcomingDepartures(fromStop stopID: String, at date: Date, limit: Int) async -> [Departure] {
        await realtime.departures(fromStop: stopID, at: date, limit: limit)
    }

    func activeAlerts(at date: Date) async -> [ServiceAlert] {
        await realtime.alerts(at: date)
    }
}
