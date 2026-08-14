import XCTest
@testable import DutchCommute

final class DecodingTests: XCTestCase {
    private func loadFixture(_ name: String) -> Data {
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: "json")!
        return try! Data(contentsOf: url)
    }

    private func firstLeg(fromFixture name: String) -> LegDTO? {
        let data = loadFixture(name)
        let response = try! JSONDecoder().decode(TripsResponse.self, from: data)
        return response.trips.first?.firstLeg
    }

    // MARK: - Trip fixtures

    func testTimeStringFromMinutes() {
        XCTAssertEqual(NSDateParser.timeString(minutes: 8 * 60 + 12), "08:12")
        XCTAssertEqual(NSDateParser.timeString(minutes: 18 * 60), "18:00")
        XCTAssertEqual(NSDateParser.timeString(minutes: 0), "00:00")
    }

    func testOnTimeFixture() throws {
        let leg = try XCTUnwrap(firstLeg(fromFixture: "trips-on-time"))
        XCTAssertEqual(leg.name, "IC 1234")
        XCTAssertEqual(leg.direction, "Utrecht Centraal")
        XCTAssertEqual(leg.cancelled, false)
        XCTAssertEqual(leg.origin?.stationCode, "ASDZ")
        let train = try XCTUnwrap(TrainLeg(dto: leg))
        XCTAssertEqual(train.status, .onTime)
        XCTAssertEqual(train.plannedDeparture, NSDateParser.parse("2026-08-14T08:11:00+0200"))
        // Tracks: actual wins over planned at the origin; planned at the destination.
        XCTAssertEqual(train.departureTrack, "6")
        XCTAssertEqual(train.arrivalTrack, "7")
    }

    func testDelayedFixture() throws {
        let leg = try XCTUnwrap(firstLeg(fromFixture: "trips-delayed"))
        let train = try XCTUnwrap(TrainLeg(dto: leg))
        XCTAssertEqual(train.status, .delayed(minutes: 8))
        XCTAssertEqual(train.actualDeparture, NSDateParser.parse("2026-08-14T08:19:41+0200"))
    }

    func testCancelledFixture() throws {
        let leg = try XCTUnwrap(firstLeg(fromFixture: "trips-cancelled"))
        let train = try XCTUnwrap(TrainLeg(dto: leg))
        XCTAssertEqual(train.status, .cancelled)
    }

    func testMissingFieldsDoNotCrash() {
        // Leg with only origin.plannedDateTime; everything else missing.
        let json = """
        {"trips":[{"legs":[{"name":null,"direction":null,"cancelled":null,
        "origin":{"plannedDateTime":"2026-08-14T08:11:00+0200","actualDateTime":null},
        "destination":null}]}]}
        """
        let data = Data(json.utf8)
        let response = try! JSONDecoder().decode(TripsResponse.self, from: data)
        let train = TrainLeg(dto: response.trips[0].legs[0])
        XCTAssertEqual(train?.name, "Train")
        XCTAssertEqual(train?.status, .onTime)
    }

    func testLegWithoutOriginTimesIsSkipped() {
        let json = """
        {"trips":[{"legs":[{"name":"IC 1234","direction":null,"cancelled":false,
        "origin":{"plannedDateTime":null},"destination":null}]}]}
        """
        let data = Data(json.utf8)
        let response = try! JSONDecoder().decode(TripsResponse.self, from: data)
        XCTAssertNil(TrainLeg(dto: response.trips[0].legs[0]))
    }

    func testProductNameFallbackWhenLegNameMissing() throws {
        let json = """
        {"trips":[{"legs":[{"name":null,"cancelled":false,
        "origin":{"plannedDateTime":"2026-08-14T08:11:00+0200"},
        "product":{"number":"1234","categoryCode":"IC"}}]}]}
        """
        let data = Data(json.utf8)
        let response = try! JSONDecoder().decode(TripsResponse.self, from: data)
        let train = try XCTUnwrap(TrainLeg(dto: response.trips[0].legs[0]))
        XCTAssertEqual(train.name, "IC 1234")
    }

    // MARK: - Date parsing

    func testDateParsingAcceptsColonAndNoColonOffsets() {
        XCTAssertEqual(
            NSDateParser.parse("2026-08-14T08:11:00+0200"),
            NSDateParser.parse("2026-08-14T08:11:00+02:00")
        )
    }

    func testDateParsingAcceptsZuluAndFractionalSeconds() {
        XCTAssertNotNil(NSDateParser.parse("2026-08-14T08:11:00Z"))
        XCTAssertNotNil(NSDateParser.parse("2026-08-14T08:11:00.123+02:00"))
        XCTAssertNil(NSDateParser.parse("not-a-date"))
    }

    // MARK: - Stations

    func testStationFilterKeepsOnlyDutchStations() throws {
        let data = loadFixture("stations")
        let response = try JSONDecoder().decode(StationsResponse.self, from: data)
        let stations = NSAPIClient.nlStations(response.payload)
        XCTAssertEqual(stations.map(\.code), ["ASDZ", "UT"])
        XCTAssertEqual(stations[0].name, "Amsterdam Zuid")
        XCTAssertEqual(stations[1].name, "Utrecht Centraal")
    }

    func testStationFilterRanking() {
        let stations = [
            Station(code: "UT", name: "Utrecht Centraal"),
            Station(code: "UTG", name: "Utrecht Overvecht"),
            Station(code: "ASD", name: "Amsterdam Centraal"),
        ]
        XCTAssertEqual(StationField.filter(stations, query: "utr").map(\.code), ["UT", "UTG"])
        XCTAssertEqual(StationField.filter(stations, query: "amsterdam").map(\.code), ["ASD"])
    }

    func testStationFilterRequiresTwoNonWhitespaceCharacters() {
        let stations = [
            Station(code: "UT", name: "Utrecht Centraal"),
            Station(code: "UTG", name: "Utrecht Overvecht"),
        ]
        XCTAssertEqual(StationField.filter(stations, query: ""), [])
        XCTAssertEqual(StationField.filter(stations, query: "u"), [])
        XCTAssertEqual(StationField.filter(stations, query: "  u  "), [])
        XCTAssertEqual(StationField.filter(stations, query: "ut").map(\.code), ["UT", "UTG"])
    }

    func testDepartureMinutesDeduplicatedSorted() throws {
        let data = loadFixture("trips-multiple")
        let response = try JSONDecoder().decode(TripsResponse.self, from: data)
        let minutes = NSAPIClient.departureMinutes(of: response.trips, calendar: JourneySchedule.calendar)
        // 07:55, 08:05 (x2, deduped), trip without origin skipped, 20:05.
        XCTAssertEqual(minutes, [475, 485, 1205])
    }

    func testTripsSearchCacheTTL() async {
        let cache = TripsSearchCache(ttl: 120)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let key = "HKS-ASD-480"

        let missing = await cache.value(for: key, now: t0)
        XCTAssertNil(missing)

        await cache.store([475, 485], for: key, now: t0)
        // Still fresh 119 seconds later; expired at exactly the TTL.
        let fresh = await cache.value(for: key, now: t0.addingTimeInterval(119))
        XCTAssertEqual(fresh, [475, 485])
        let expired = await cache.value(for: key, now: t0.addingTimeInterval(120))
        XCTAssertNil(expired)

        // Entries are independent; never-stored keys return nil.
        await cache.store([1205], for: "UT-ASD-1080", now: t0)
        let other = await cache.value(for: "ASD-UT-480", now: t0.addingTimeInterval(119))
        XCTAssertNil(other)
    }

    func testJourneyConfigViaCodableRoundTrip() throws {
        let config = JourneyConfig(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_000),
            from: Station(code: "HKS", name: "Hoogkarspel"),
            via: Station(code: "HNB", name: "Hoorn"),
            to: Station(code: "ASD", name: "Amsterdam Centraal"),
            departMinutes: 480,
            returnMinutes: 1080,
            days: [.monday, .friday],
            transportModes: [.train, .bus]
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(JourneyConfig.self, from: data)
        XCTAssertEqual(decoded.via, Station(code: "HNB", name: "Hoorn"))
        XCTAssertEqual(decoded.transportModes, [.train, .bus])
        XCTAssertEqual(decoded.departMinutes, 480)
    }

    func testJourneyConfigOldFormatDecodesWithDefaults() throws {
        // A config persisted before `via`/`transportModes` existed must
        // still decode: via nil, all transport modes selected.
        let json = #"{"id":"11111111-1111-1111-1111-111111111111","createdAt":0,"from":{"code":"HKS","name":"Hoogkarspel"},"to":{"code":"ASD","name":"Amsterdam Centraal"},"departMinutes":480,"returnMinutes":1080,"days":[1,2]}"#
        let decoded = try JSONDecoder().decode(JourneyConfig.self, from: Data(json.utf8))
        XCTAssertNil(decoded.via)
        XCTAssertEqual(decoded.transportModes, Set(TransportMode.allCases))
        XCTAssertEqual(decoded.from.code, "HKS")
    }

    func testJourneyConfigLegacySingleModeDecodes() throws {
        // Configs saved when `transportMode` was a single value still work.
        let json = #"{"id":"11111111-1111-1111-1111-111111111111","createdAt":0,"from":{"code":"HKS","name":"Hoogkarspel"},"to":{"code":"ASD","name":"Amsterdam Centraal"},"departMinutes":480,"returnMinutes":1080,"days":[1,2],"transportMode":"bus"}"#
        let decoded = try JSONDecoder().decode(JourneyConfig.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.transportModes, [.bus])
    }

    func testDisabledModalityCodes() {
        let all = Set(TransportMode.allCases)
        XCTAssertEqual(TransportMode.disabledModalityCodes(keeping: all), "")
        XCTAssertEqual(TransportMode.disabledModalityCodes(keeping: [.train]), "BUS,METRO,TRAM,FERRY")
        XCTAssertEqual(TransportMode.disabledModalityCodes(keeping: [.train, .bus]), "METRO,TRAM,FERRY")
        XCTAssertEqual(TransportMode.disabledModalityCodes(keeping: [.ferry]), "TRAIN,BUS,METRO,TRAM")
    }
}
