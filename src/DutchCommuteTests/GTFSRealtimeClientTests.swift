import XCTest
@testable import DutchCommute

final class GTFSRealtimeClientTests: XCTestCase {
    private let feed = GTFSRealtimeFeed(id: "test", url: URL(string: "https://example.invalid/feed.pb")!)

    /// A fresh feed timestamp.
    private var now: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    // MARK: - Fixtures built with the generated protobuf types

    private func message(headerTimestamp: UInt64, entities: [TransitRealtime_FeedEntity]) -> Data {
        var message = TransitRealtime_FeedMessage()
        message.header.gtfsRealtimeVersion = "2.0"
        message.header.timestamp = headerTimestamp
        message.entity = entities
        return try! message.serializedData()
    }

    private func tripUpdateEntity(
        tripID: String = "trip-1",
        routeID: String = "route-38",
        tripCancelled: Bool = false,
        stopUpdates: [(stopID: String, sequence: UInt32, delay: Int32, skip: Bool)] = []
    ) -> TransitRealtime_FeedEntity {
        var entity = TransitRealtime_FeedEntity()
        entity.id = "tu-1"
        entity.tripUpdate.trip.tripID = tripID
        entity.tripUpdate.trip.routeID = routeID
        entity.tripUpdate.trip.scheduleRelationship = tripCancelled ? .canceled : .scheduled
        for update in stopUpdates {
            var stopTime = TransitRealtime_TripUpdate.StopTimeUpdate()
            stopTime.stopID = update.stopID
            stopTime.stopSequence = update.sequence
            stopTime.departure.delay = update.delay
            if update.skip {
                stopTime.scheduleRelationship = .skipped
            }
            entity.tripUpdate.stopTimeUpdate.append(stopTime)
        }
        return entity
    }

    private func alertEntity(
        id: String = "alert-1",
        header: String = "Ombouw werkzaamheden",
        description: String = "Trein rijdt niet",
        cause: TransitRealtime_Alert.Cause = .maintenance,
        effect: TransitRealtime_Alert.Effect = .noService,
        start: UInt64 = 1_700_000_000,
        end: UInt64 = 1_900_000_000,
        routeID: String = "route-38",
        stopID: String = "stop-1"
    ) -> TransitRealtime_FeedEntity {
        var entity = TransitRealtime_FeedEntity()
        entity.id = id
        entity.alert.cause = cause
        entity.alert.effect = effect
        var period = TransitRealtime_TimeRange()
        period.start = start
        period.end = end
        entity.alert.activePeriod = [period]
        var selector = TransitRealtime_EntitySelector()
        selector.routeID = routeID
        selector.stopID = stopID
        entity.alert.informedEntity = [selector]
        var headerText = TransitRealtime_Translation()
        headerText.text = header
        var headerString = TransitRealtime_TranslatedString()
        headerString.translation = [headerText]
        entity.alert.headerText = headerString
        var descriptionText = TransitRealtime_Translation()
        descriptionText.text = description
        var descriptionString = TransitRealtime_TranslatedString()
        descriptionString.translation = [descriptionText]
        entity.alert.descriptionText = descriptionString
        return entity
    }

    // MARK: - Trip updates

    func testDecodesTripUpdateWithDelay() throws {
        let data = message(headerTimestamp: 1_800_000_000, entities: [
            tripUpdateEntity(stopUpdates: [(stopID: "stop-1", sequence: 1, delay: 300, skip: false)]),
        ])
        let decoded = try GTFSRealtimeClient.decode(data, feed: feed, now: now)

        XCTAssertEqual(decoded.tripUpdates.count, 1)
        let update = try XCTUnwrap(decoded.tripUpdates.first)
        XCTAssertEqual(update.tripID, "trip-1")
        XCTAssertEqual(update.routeID, "route-38")
        XCTAssertFalse(update.tripCancelled)
        XCTAssertEqual(update.stopTimeUpdates.count, 1)
        XCTAssertEqual(update.stopTimeUpdates.first?.departureDelay, 300)
        XCTAssertEqual(update.stopTimeUpdates.first?.scheduleRelationship, "SCHEDULED")
    }

    func testDecodesCancelledTripAndSkippedStop() throws {
        let data = message(headerTimestamp: 1_800_000_000, entities: [
            tripUpdateEntity(tripCancelled: true),
            tripUpdateEntity(tripID: "trip-2", stopUpdates: [(stopID: "stop-1", sequence: 1, delay: 0, skip: true)]),
        ])
        let decoded = try GTFSRealtimeClient.decode(data, feed: feed, now: now)

        XCTAssertEqual(decoded.tripUpdates.count, 2)
        XCTAssertTrue(decoded.tripUpdates[0].tripCancelled)
        XCTAssertEqual(decoded.tripUpdates[1].stopTimeUpdates.first?.scheduleRelationship, "SKIPPED")
    }

    func testDecodesAlert() throws {
        let data = message(headerTimestamp: 1_800_000_000, entities: [alertEntity()])
        let decoded = try GTFSRealtimeClient.decode(data, feed: feed, now: now)

        let alert = try XCTUnwrap(decoded.alerts.first)
        XCTAssertEqual(alert.id, "alert-1")
        XCTAssertEqual(alert.header, "Ombouw werkzaamheden")
        XCTAssertEqual(alert.summary, "Trein rijdt niet")
        XCTAssertEqual(alert.cause, "MAINTENANCE")
        XCTAssertEqual(alert.effect, "NO_SERVICE")
        XCTAssertEqual(alert.startDate, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(alert.endDate, Date(timeIntervalSince1970: 1_900_000_000))
        XCTAssertEqual(alert.routeIDs, ["route-38"])
        XCTAssertEqual(alert.stopIDs, ["stop-1"])
    }

    func testDecodesVehiclePosition() throws {
        var entity = TransitRealtime_FeedEntity()
        entity.id = "v-1"
        entity.vehicle.trip.tripID = "trip-1"
        entity.vehicle.stopID = "stop-2"
        entity.vehicle.position.latitude = 52.09
        entity.vehicle.position.longitude = 5.12
        entity.vehicle.timestamp = 1_800_000_000
        let data = message(headerTimestamp: 1_800_000_000, entities: [entity])

        let decoded = try GTFSRealtimeClient.decode(data, feed: feed, now: now)
        let vehicle = try XCTUnwrap(decoded.vehiclePositions.first)
        XCTAssertEqual(vehicle.tripID, "trip-1")
        XCTAssertEqual(vehicle.stopID, "stop-2")
        XCTAssertEqual(vehicle.latitude ?? 0, 52.09, accuracy: 0.001)
        XCTAssertEqual(vehicle.longitude ?? 0, 5.12, accuracy: 0.001)
    }

    // MARK: - Independent raw-bytes fixture (wire format)

    func testDecodesRawProtobufBytes() throws {
        // Hand-crafted FeedMessage with one FeedEntity carrying a TripUpdate:
        //  - field 1 (header): FeedHeader{ version="2.0" (field1), timestamp=100 (field2) }
        //  - field 2 (entity): FeedEntity{ id="e1" (field1) }
        var bytes = Data()
        // Header: length-delimited (field 1, wire type 2)
        let header = Data([0x0A, 0x03, 0x32, 0x2E, 0x30, // version "2.0"
                           0x10, 0x64])                // timestamp = 100
        bytes.append(0x0A)
        bytes.append(UInt8(header.count))
        bytes.append(header)
        // Entity: length-delimited (field 2, wire type 2)
        let entity = Data([0x0A, 0x02, 0x65, 0x31])     // id = "e1"
        bytes.append(0x12)
        bytes.append(UInt8(entity.count))
        bytes.append(entity)

        let decoded = try GTFSRealtimeClient.decode(bytes, feed: feed, now: Date(timeIntervalSince1970: 150))
        XCTAssertEqual(decoded.tripUpdates, [])
        XCTAssertEqual(decoded.alerts, [])
        XCTAssertEqual(decoded.feedTimestamp, Date(timeIntervalSince1970: 100))
    }

    // MARK: - Error handling

    func testMalformedFeedThrows() {
        let garbage = Data([0xFF, 0x00, 0x81, 0x99, 0x42])
        XCTAssertThrowsError(try GTFSRealtimeClient.decode(garbage, feed: feed, now: now)) { error in
            guard case GTFSRealtimeError.malformedFeed = error else {
                return XCTFail("expected malformedFeed, got \(error)")
            }
        }
    }

    func testStaleFeedThrows() {
        let data = message(headerTimestamp: 100, entities: []) // 1800s old
        XCTAssertThrowsError(try GTFSRealtimeClient.decode(data, feed: feed, now: now)) { error in
            guard case GTFSRealtimeError.staleFeed = error else {
                return XCTFail("expected staleFeed, got \(error)")
            }
        }
    }
}
