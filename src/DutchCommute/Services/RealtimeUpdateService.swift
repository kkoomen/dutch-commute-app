import Foundation

/// Combines static GTFS with live GTFS-Realtime feeds into domain
/// `Departure`s and `ServiceAlert`s. Feed failures and stale feeds degrade
/// gracefully to scheduled-only data.
struct RealtimeUpdateService {
    let staticData: GTFSStaticData
    let feeds: [GTFSRealtimeFeed]
    let client: GTFSRealtimeClient

    init(staticData: GTFSStaticData, feeds: [GTFSRealtimeFeed], client: GTFSRealtimeClient = GTFSRealtimeClient()) {
        self.staticData = staticData
        self.feeds = feeds
        self.client = client
    }

    /// Upcoming departures from a stop: scheduled stop times joined with
    /// live trip updates (delays, cancellations). Scheduled-only when the
    /// feeds fail or are stale.
    func departures(fromStop stopID: String, at date: Date, limit: Int = 10) async -> [Departure] {
        var updates: [GTFSRealtimeTripUpdate] = []
        for feed in feeds where feed.providesTripUpdates {
            if let data = try? await client.fetch(feed, now: date) {
                updates.append(contentsOf: data.tripUpdates)
            }
        }
        return Self.joinedDepartures(fromStop: stopID, at: date, staticData: staticData, tripUpdates: updates, limit: limit)
    }

    /// Active alerts from the feeds.
    func alerts(at date: Date) async -> [ServiceAlert] {
        var alerts: [GTFSRealtimeAlert] = []
        for feed in feeds where feed.providesAlerts {
            if let data = try? await client.fetch(feed, now: date) {
                alerts.append(contentsOf: data.alerts)
            }
        }
        return Self.mappedAlerts(alerts, at: date)
    }

    // MARK: Pure join (testable without network)

    /// Joins static stop times with live trip updates into departures.
    static func joinedDepartures(
        fromStop stopID: String,
        at date: Date,
        staticData: GTFSStaticData,
        tripUpdates: [GTFSRealtimeTripUpdate],
        limit: Int
    ) -> [Departure] {
        let calendar = JourneySchedule.calendar
        let startOfDay = calendar.startOfDay(for: date)
        let updatesByTrip = Dictionary(grouping: tripUpdates, by: \.tripID)

        var departures: [Departure] = []
        for stopTime in staticData.stopTimes.filter({ $0.stopID == stopID }) {
            guard let trip = staticData.trips[stopTime.tripID],
                  let route = staticData.routes[trip.routeID],
                  let mode = TransportMode(gtfsRouteType: route.routeType),
                  let departureSeconds = stopTime.departureSeconds
            else { continue }

            let scheduled = startOfDay.addingTimeInterval(TimeInterval(departureSeconds))
            guard scheduled >= date else { continue } // only upcoming

            let stop = staticData.stops[stopID]
            let live = updatesByTrip[trip.id]?.first
            let stopUpdate = live?.stopTimeUpdates.first {
                ($0.stopID ?? "") == stopID || $0.stopSequence == stopTime.stopSequence
            }

            let isCancelled = stopUpdate?.scheduleRelationship == "SKIPPED" || live?.tripCancelled == true

            let delay = stopUpdate?.departureDelay ?? stopUpdate?.arrivalDelay
            let actual = stopUpdate?.departureTime ?? stopUpdate?.arrivalTime
            let displayedTime = actual ?? scheduled.addingTimeInterval(TimeInterval(delay ?? 0))

            let status: TrainStatus
            if isCancelled {
                status = .cancelled
            } else if let delay, delay > 0 {
                status = .delayed(minutes: Int(delay) / 60)
            } else {
                status = .onTime
            }

            let routeName = route.shortName.flatMap { !$0.isEmpty ? $0 : nil }
                ?? route.longName ?? trip.routeID

            departures.append(Departure(
                id: "gtfs-\(trip.id)-\(stopID)",
                mode: mode,
                routeName: routeName,
                destination: staticData.destination(of: trip),
                stopID: stopID,
                stopName: stop?.name ?? stopID,
                scheduledDeparture: scheduled,
                actualDeparture: actual ?? (delay.map { scheduled.addingTimeInterval(TimeInterval($0)) }),
                status: status,
                tripID: trip.id
            ))
        }

        return departures.sorted { $0.scheduledDeparture < $1.scheduledDeparture }.prefix(limit).map { $0 }
    }

    /// Maps decoded alerts to domain alerts, keeping only those active
    /// around `date` (or without an active period).
    static func mappedAlerts(_ alerts: [GTFSRealtimeAlert], at date: Date) -> [ServiceAlert] {
        alerts.compactMap { alert in
            if let start = alert.startDate, start > date { return nil }
            if let end = alert.endDate, end < date { return nil }
            return ServiceAlert(
                id: alert.id,
                header: alert.header,
                summary: alert.summary,
                cause: alert.cause,
                effect: alert.effect,
                startDate: alert.startDate,
                endDate: alert.endDate,
                affectedRouteIDs: alert.routeIDs,
                affectedStopIDs: alert.stopIDs
            )
        }
    }
}
