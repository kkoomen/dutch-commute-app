import XCTest
@testable import DutchCommute

final class RealtimeUpdateServiceTests: XCTestCase {
    /// Fixed "now" so the scheduled times in fixtures are deterministic.
    private var now: Date {
        let calendar = JourneySchedule.calendar
        return calendar.date(bySettingHour: 7, minute: 30, second: 0, of: Date(timeIntervalSince1970: 1_800_000_000))!
    }

    private var staticData: GTFSStaticData {
        try! GTFSStaticDataService.load(
            stopsCSV: """
            stop_id,stop_name,stop_lat,stop_lon
            stop-1,Centraal Station,52.09,5.12
            stop-2,Station Zuid,52.12,5.14
            """,
            routesCSV: """
            route_id,route_short_name,route_long_name,route_type
            route-38,38,Centrum - Station,3
            route-9,9,Spoorzone,0
            """,
            tripsCSV: """
            trip_id,route_id,trip_headsign
            trip-1,route-38,Station Zuid
            trip-2,route-9,Markt
            trip-3,route-38,Station Zuid
            """,
            stopTimesCSV: """
            trip_id,stop_id,stop_sequence,departure_time
            trip-1,stop-1,1,08:00:00
            trip-2,stop-1,1,08:05:00
            trip-3,stop-1,1,08:10:00
            trip-3,stop-2,2,08:20:00
            """
        )
    }

    private func update(tripID: String, delay: Int32, skip: Bool = false, cancelled: Bool = false) -> GTFSRealtimeTripUpdate {
        GTFSRealtimeTripUpdate(
            tripID: tripID,
            routeID: "route-38",
            tripCancelled: cancelled,
            stopTimeUpdates: [
                GTFSRealtimeStopTimeUpdate(
                    stopID: "stop-1",
                    stopSequence: 1,
                    arrivalDelay: delay,
                    departureDelay: delay,
                    arrivalTime: nil,
                    departureTime: nil,
                    scheduleRelationship: skip ? "SKIPPED" : "SCHEDULED"
                )
            ],
            timestamp: nil
        )
    }

    func testScheduledOnlyWithoutUpdates() {
        let departures = RealtimeUpdateService.joinedDepartures(
            fromStop: "stop-1", at: now, staticData: staticData, tripUpdates: [], limit: 10
        )
        XCTAssertEqual(departures.map(\.tripID), ["trip-1", "trip-2", "trip-3"])
        XCTAssertEqual(departures.map(\.status), [.onTime, .onTime, .onTime])
        XCTAssertEqual(departures.first?.mode, .bus)
        XCTAssertEqual(departures.first?.routeName, "38")
        XCTAssertEqual(departures.first?.destination, "Station Zuid")
        XCTAssertEqual(departures.first?.scheduledDeparture, now.addingTimeInterval(30 * 60))
    }

    func testDelayAppliedAndSorted() {
        let updates = [
            update(tripID: "trip-1", delay: 300),   // +5 min
            update(tripID: "trip-3", delay: 600),   // +10 min
        ]
        let departures = RealtimeUpdateService.joinedDepartures(
            fromStop: "stop-1", at: now, staticData: staticData, tripUpdates: updates, limit: 10
        )
        // Order stays by scheduled departure; the delayed times are applied.
        XCTAssertEqual(departures.map(\.tripID), ["trip-1", "trip-2", "trip-3"])
        XCTAssertEqual(departures[0].status, .delayed(minutes: 5))
        XCTAssertEqual(departures[1].status, .onTime)
        XCTAssertEqual(departures[2].status, .delayed(minutes: 10))
        XCTAssertEqual(departures[0].actualDeparture, now.addingTimeInterval(35 * 60))
    }

    func testCancelledTripAndSkippedStop() {
        let updates = [
            update(tripID: "trip-1", delay: 0, cancelled: true),
            update(tripID: "trip-2", delay: 0, skip: true),
        ]
        let departures = RealtimeUpdateService.joinedDepartures(
            fromStop: "stop-1", at: now, staticData: staticData, tripUpdates: updates, limit: 10
        )
        XCTAssertEqual(departures.map(\.status), [.cancelled, .cancelled, .onTime])
        XCTAssertEqual(departures.map(\.tripID), ["trip-1", "trip-2", "trip-3"])
    }

    func testPastDeparturesAreFiltered() {
        let departures = RealtimeUpdateService.joinedDepartures(
            fromStop: "stop-1", at: now.addingTimeInterval(3 * 3600), // 10:30 — all departures are past
            staticData: staticData, tripUpdates: [], limit: 10
        )
        XCTAssertTrue(departures.isEmpty)
    }

    func testLimitApplies() {
        let departures = RealtimeUpdateService.joinedDepartures(
            fromStop: "stop-1", at: now, staticData: staticData, tripUpdates: [], limit: 2
        )
        XCTAssertEqual(departures.count, 2)
    }

    func testUnknownModeSkipped() {
        // A route with an unsupported route_type (5 = cable car) is skipped.
        let data = try! GTFSStaticDataService.load(
            stopsCSV: """
            stop_id,stop_name,stop_lat,stop_lon
            stop-1,Centraal Station,52.09,5.12
            """,
            routesCSV: """
            route_id,route_short_name,route_long_name,route_type
            route-38,38,Centrum - Station,3
            route-5,5,Kabelbaan,5
            """,
            tripsCSV: """
            trip_id,route_id,trip_headsign
            trip-1,route-38,Station Zuid
            trip-2,route-5,Bergtop
            """,
            stopTimesCSV: """
            trip_id,stop_id,stop_sequence,departure_time
            trip-1,stop-1,1,08:00:00
            trip-2,stop-1,1,08:05:00
            """
        )
        let departures = RealtimeUpdateService.joinedDepartures(
            fromStop: "stop-1", at: now, staticData: data, tripUpdates: [], limit: 10
        )
        XCTAssertEqual(departures.map(\.tripID), ["trip-1"])
    }

    func testAlertsFilteredByActivePeriod() {
        let alerts = [
            GTFSRealtimeAlert(id: "a1", header: "H", summary: "S", cause: "MAINTENANCE", effect: "NO_SERVICE",
                              startDate: now.addingTimeInterval(-3600), endDate: now.addingTimeInterval(3600),
                              routeIDs: ["route-38"], stopIDs: ["stop-1"]),
            GTFSRealtimeAlert(id: "a2", header: "H", summary: "S", cause: "WEATHER", effect: "DETOUR",
                              startDate: now.addingTimeInterval(3600), endDate: now.addingTimeInterval(7200),
                              routeIDs: [], stopIDs: []), // starts in the future → filtered out
            GTFSRealtimeAlert(id: "a3", header: "H", summary: "S", cause: "STRIKE", effect: "NO_SERVICE",
                              startDate: nil, endDate: nil, routeIDs: [], stopIDs: []), // no period → active
        ]
        let mapped = RealtimeUpdateService.mappedAlerts(alerts, at: now)
        XCTAssertEqual(mapped.map(\.id), ["a1", "a3"])
        XCTAssertEqual(mapped.first?.cause, "MAINTENANCE")
        XCTAssertEqual(mapped.first?.affectedRouteIDs, ["route-38"])
    }
}
