import XCTest
@testable import DutchCommuteWidget

final class StatusMappingTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testOnTimeWhenNoActualTime() {
        XCTAssertEqual(
            TrainStatusMapping.status(cancelled: false, plannedDeparture: base, actualDeparture: nil),
            .onTime
        )
    }

    func testOnTimeWhenActualEqualsPlanned() {
        XCTAssertEqual(
            TrainStatusMapping.status(cancelled: false, plannedDeparture: base, actualDeparture: base),
            .onTime
        )
    }

    func testOnTimeWhenActualEarlierThanPlanned() {
        XCTAssertEqual(
            TrainStatusMapping.status(cancelled: false, plannedDeparture: base, actualDeparture: base.addingTimeInterval(-60)),
            .onTime
        )
    }

    func testDelayedRoundsDownToWholeMinutes() {
        // 8 minutes 41 seconds late → +8 min
        XCTAssertEqual(
            TrainStatusMapping.status(cancelled: false, plannedDeparture: base, actualDeparture: base.addingTimeInterval(8 * 60 + 41)),
            .delayed(minutes: 8)
        )
    }

    func testDelayedWholeMinutes() {
        XCTAssertEqual(
            TrainStatusMapping.status(cancelled: false, plannedDeparture: base, actualDeparture: base.addingTimeInterval(8 * 60)),
            .delayed(minutes: 8)
        )
    }

    func testCancelledWinsOverDelay() {
        XCTAssertEqual(
            TrainStatusMapping.status(cancelled: true, plannedDeparture: base, actualDeparture: base.addingTimeInterval(8 * 60)),
            .cancelled
        )
    }

    func testCancelledWithoutTimes() {
        XCTAssertEqual(
            TrainStatusMapping.status(cancelled: true, plannedDeparture: nil, actualDeparture: nil),
            .cancelled
        )
    }

    func testUnknownWhenNoPlannedTime() {
        XCTAssertEqual(
            TrainStatusMapping.status(cancelled: false, plannedDeparture: nil, actualDeparture: nil),
            .unknown
        )
    }
}
