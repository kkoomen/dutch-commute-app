import XCTest
@testable import TravelScreen

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

    func testOnTimeFixture() throws {
        let leg = try XCTUnwrap(firstLeg(fromFixture: "trips-on-time"))
        XCTAssertEqual(leg.name, "IC 1234")
        XCTAssertEqual(leg.direction, "Utrecht Centraal")
        XCTAssertEqual(leg.cancelled, false)
        XCTAssertEqual(leg.origin?.stationCode, "ASDZ")
        let train = try XCTUnwrap(TrainLeg(dto: leg))
        XCTAssertEqual(train.status, .onTime)
        XCTAssertEqual(train.plannedDeparture, NSDateParser.parse("2026-08-14T08:11:00+0200"))
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
}
