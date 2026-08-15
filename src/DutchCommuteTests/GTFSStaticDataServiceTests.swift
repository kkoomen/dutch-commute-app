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

    // MARK: - Stop departures

    func testParseDepartureMinutesBinary() {
        var blob = Data()
        blob.append(contentsOf: [0xE9, 0x03, 0x00, 0x00, 0x02, 0x00]) // stop 1001, count 2
        blob.append(contentsOf: [0xE0, 0x01, 0x58, 0x02])             // minutes 480, 600
        blob.append(contentsOf: [0xD2, 0x07, 0x00, 0x00, 0x03, 0x00]) // stop 2002, count 3
        blob.append(contentsOf: [0x3C, 0x00, 0x78, 0x00, 0xB4, 0x00]) // minutes 60, 120, 180
        let parsed = GTFSStaticDataService.parseDepartureMinutes(blob)
        XCTAssertEqual(parsed["1001"], [480, 600])
        XCTAssertEqual(parsed["2002"], [60, 120, 180])
        XCTAssertEqual(parsed.count, 2)
    }

    /// A small gzip'd binary blob, generated with Python's gzip module.
    func testGunzipAndParse() {
        let base64 = "H4sIALAtgGoC/3vJzMDAxPCAMYLpEjsDAzODDUMFwxYGAPqsVJcWAAAA"
        let gz = Data(base64Encoded: base64)!
        let parsed = GTFSStaticDataService.parseDepartureMinutes(
            GTFSStaticDataService.gunzip(gz)!
        )
        XCTAssertEqual(parsed["1001"], [480, 600])
        XCTAssertEqual(parsed["2002"], [60, 120, 180])
    }

    func testDepartureMinutesFromPreferredTime() {
        let data = ["1001": [420, 480, 600, 720, 900]]
        let calendar = JourneySchedule.calendar
        let preferred = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 8))! // 480
        XCTAssertEqual(
            GTFSStaticDataService.departureMinutes(from: "1001", data: data, at: preferred, calendar: calendar),
            [480, 600, 720, 900]
        )
        let capped = GTFSStaticDataService.departureMinutes(from: "1001", data: data, at: preferred, limit: 2, calendar: calendar)
        XCTAssertEqual(capped, [480, 600])
        XCTAssertEqual(
            GTFSStaticDataService.departureMinutes(from: "9999", data: data, at: preferred, calendar: calendar),
            []
        )
    }

    /// The real bundled departures file decompresses and covers the stops.
    func testBundledDeparturesLoad() {
        guard let url = Bundle(for: GTFSStaticDataServiceTests.self).url(forResource: "gtfs", withExtension: nil) else {
            return XCTFail("bundled gtfs folder missing")
        }
        let minutes = GTFSStaticDataService.loadDepartureMinutes(
            from: url.appendingPathComponent("departures.bin.gz")
        )
        XCTAssertGreaterThan(minutes.count, 50_000)
        XCTAssertFalse(minutes["2860212"]?.isEmpty ?? true)
    }

    func testUsesNSAPIByMode() {
        let train = Station(code: "UT", name: "Utrecht Centraal")
        let bus = Station(code: "BUS1", name: "Busplein")
        let choices = [
            StationChoice(id: "UT", name: "Utrecht Centraal", mode: .train),
            StationChoice(id: "BUS1", name: "Busplein", mode: .bus),
        ]
        // Routing is based on the leg's departure stop only.
        XCTAssertTrue(AppState.usesNSAPI(departureStop: train, choices: choices))
        XCTAssertFalse(AppState.usesNSAPI(departureStop: bus, choices: choices))
        // Unknown stops fall back to the NS API.
        XCTAssertTrue(AppState.usesNSAPI(departureStop: Station(code: "ZZZ", name: "X"), choices: choices))
        // No choices loaded yet → NS API (historical default).
        XCTAssertTrue(AppState.usesNSAPI(departureStop: train, choices: []))
    }
}
