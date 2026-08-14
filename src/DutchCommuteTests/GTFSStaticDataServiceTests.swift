import XCTest
@testable import DutchCommute

final class GTFSStaticDataServiceTests: XCTestCase {
    private let stopsCSV = """
    stop_id,stop_name,stop_lat,stop_lon
    stop-1,Centraal Station,52.09,5.12
    stop-2,"Hoofdstraat, Oost",52.11,5.13
    stop-3,Station Zuid,52.12,5.14
    """

    private let routesCSV = """
    route_id,route_short_name,route_long_name,route_type
    route-38,38,Centrum - Station,3
    route-9,9,Spoorzone,0
    route-IC,IC,Intercity,2
    """

    private let tripsCSV = """
    trip_id,route_id,trip_headsign
    trip-1,route-38,Station Zuid
    trip-2,route-9,Markt
    trip-4,route-38,
    """

    private let stopTimesCSV = """
    trip_id,stop_id,stop_sequence,departure_time
    trip-1,stop-1,1,08:00:00
    trip-1,stop-3,2,08:12:00
    trip-2,stop-1,1,25:00:00
    trip-4,stop-3,1,09:00:00
    """

    func testLoadsAndLooksUp() throws {
        let data = try GTFSStaticDataService.load(
            stopsCSV: stopsCSV,
            routesCSV: routesCSV,
            tripsCSV: tripsCSV,
            stopTimesCSV: stopTimesCSV
        )

        XCTAssertEqual(data.stops["stop-1"]?.name, "Centraal Station")
        // Quoted field with comma survives CSV parsing.
        XCTAssertEqual(data.stops["stop-2"]?.name, "Hoofdstraat, Oost")
        XCTAssertEqual(data.routes["route-38"]?.routeType, 3)
        XCTAssertEqual(data.trips["trip-1"]?.headsign, "Station Zuid")

        let times = data.stopTimes(tripID: "trip-1")
        XCTAssertEqual(times.map(\.stopSequence), [1, 2])
        XCTAssertEqual(times.first?.departureSeconds, 8 * 3600)
    }

    func testSecondsOfDayBeyondMidnight() {
        XCTAssertEqual(GTFSStaticDataService.secondsOfDay("25:00:00"), 25 * 3600)
        XCTAssertEqual(GTFSStaticDataService.secondsOfDay("08:12:30"), 8 * 3600 + 12 * 60 + 30)
        XCTAssertNil(GTFSStaticDataService.secondsOfDay("08:12"))
        XCTAssertNil(GTFSStaticDataService.secondsOfDay("abc"))
    }

    func testDestinationUsesHeadsignThenLastStop() {
        let data = try! GTFSStaticDataService.load(
            stopsCSV: stopsCSV,
            routesCSV: routesCSV,
            tripsCSV: tripsCSV,
            stopTimesCSV: stopTimesCSV
        )
        XCTAssertEqual(data.destination(of: data.trips["trip-1"]!), "Station Zuid")

        // Without a headsign the destination comes from the last stop name.
        XCTAssertEqual(data.destination(of: data.trips["trip-4"]!), "Station Zuid")
    }

    func testTransportModeFromGtfsRouteType() {
        XCTAssertEqual(TransportMode(gtfsRouteType: 0), .tram)
        XCTAssertEqual(TransportMode(gtfsRouteType: 1), .metro)
        XCTAssertEqual(TransportMode(gtfsRouteType: 2), .train)
        XCTAssertEqual(TransportMode(gtfsRouteType: 3), .bus)
        XCTAssertEqual(TransportMode(gtfsRouteType: 4), .ferry)
        XCTAssertNil(TransportMode(gtfsRouteType: 5))
        XCTAssertNil(TransportMode(gtfsRouteType: 100))
    }

    func testStationChoicesFromGtfsData() throws {
        let data = try GTFSStaticDataService.load(
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
            """,
            stopTimesCSV: """
            trip_id,stop_id,stop_sequence,departure_time
            trip-1,stop-1,1,08:00:00
            trip-1,stop-2,2,08:12:00
            trip-2,stop-1,1,08:05:00
            """
        )
        let choices = GTFSStaticDataService.stationChoices(from: data)
        // stop-1 is served by a bus and a tram route → two choices.
        XCTAssertEqual(choices.count, 3)
        XCTAssertTrue(choices.contains(StationChoice(id: "stop-1", name: "Centraal Station", mode: .bus)))
        XCTAssertTrue(choices.contains(StationChoice(id: "stop-1", name: "Centraal Station", mode: .tram)))
        XCTAssertTrue(choices.contains(StationChoice(id: "stop-2", name: "Station Zuid", mode: .bus)))
        // Sorted by name.
        XCTAssertEqual(choices.map(\.name), ["Centraal Station", "Centraal Station", "Station Zuid"])
    }

    /// The compact picker format: stops.txt + stop_modes.txt.
    func testStationChoicesFromCompactStopModes() throws {
        let data = try GTFSStaticDataService.load(
            stopsCSV: """
            stop_id,stop_name,stop_lat,stop_lon
            stop-1,Centraal Station,52.09,5.12
            stop-2,Station Zuid,52.12,5.14
            """,
            routesCSV: "",
            tripsCSV: "",
            stopTimesCSV: "",
            stopModesCSV: """
            stop_id,route_types
            stop-1,"0,3"
            stop-2,3
            """
        )
        XCTAssertEqual(data.stopModes["stop-1"], [0, 3])
        let choices = GTFSStaticDataService.stationChoices(from: data)
        XCTAssertTrue(choices.contains(StationChoice(id: "stop-1", name: "Centraal Station", mode: .tram)))
        XCTAssertTrue(choices.contains(StationChoice(id: "stop-1", name: "Centraal Station", mode: .bus)))
        XCTAssertTrue(choices.contains(StationChoice(id: "stop-2", name: "Station Zuid", mode: .bus)))
    }

    /// The real bundled dataset parses and yields a large choice list.
    func testBundledGtfsDatasetLoads() throws {
        guard let url = Bundle(for: GTFSStaticDataServiceTests.self).url(forResource: "gtfs", withExtension: nil) else {
            return XCTFail("bundled gtfs folder missing")
        }
        let data = try GTFSStaticDataService.load(from: url)
        XCTAssertGreaterThan(data.stops.count, 50_000)
        XCTAssertFalse(data.stopModes.isEmpty)
        let choices = GTFSStaticDataService.stationChoices(from: data)
        XCTAssertGreaterThan(choices.count, 50_000)
        // NL GTFS stop names use the "[Station] …" convention.
        XCTAssertTrue(choices.contains { $0.name.contains("Utrecht Centraal") })
        XCTAssertTrue(choices.contains { $0.mode == .bus })
        XCTAssertTrue(choices.contains { $0.mode == .tram })
    }
}
