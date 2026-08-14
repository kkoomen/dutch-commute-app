import XCTest
@testable import TravelScreen

final class JourneyScheduleTests: XCTestCase {
    private let calendar = JourneySchedule.calendar

    /// Amsterdam 2025-02-19 is a Wednesday.
    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2025, month: 2, day: day, hour: hour, minute: minute))!
    }

    private func config(days: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]) -> JourneyConfig {
        JourneyConfig(
            from: Station(code: "ASDZ", name: "Amsterdam Zuid"),
            to: Station(code: "UT", name: "Utrecht Centraal"),
            departMinutes: 8 * 60 + 11,
            returnMinutes: 18 * 60 + 13,
            days: days
        )
    }

    // MARK: - Active journey date

    func testShowsTodayWhileBeforeReturnTime() {
        let now = date(19, 10, 0) // Wed 10:00
        XCTAssertEqual(
            JourneySchedule.nextJourneyDate(now: now, config: config()),
            calendar.startOfDay(for: date(19, 0, 0))
        )
    }

    func testShowsTodayExactlyAtReturnTime() {
        let now = date(19, 18, 13)
        XCTAssertEqual(
            JourneySchedule.nextJourneyDate(now: now, config: config()),
            calendar.startOfDay(for: date(19, 0, 0))
        )
    }

    func testShowsNextDayOneMinuteAfterReturnTime() {
        let now = date(19, 18, 14) // Wed 18:14 → Thursday's journey
        XCTAssertEqual(
            JourneySchedule.nextJourneyDate(now: now, config: config()),
            calendar.startOfDay(for: date(20, 0, 0))
        )
    }

    func testSkipsUnconfiguredWeekend() {
        let now = date(22, 10, 0) // Sat 10:00 → Monday
        XCTAssertEqual(
            JourneySchedule.nextJourneyDate(now: now, config: config()),
            calendar.startOfDay(for: date(24, 0, 0))
        )
    }

    func testWrapsAroundWeekWhenNothingConfigured() {
        let config = config(days: [.friday]) // 2025-02-19 is Wed
        let now = date(19, 20, 0) // Wed 20:00, after return → Friday 21st
        XCTAssertEqual(
            JourneySchedule.nextJourneyDate(now: now, config: config),
            calendar.startOfDay(for: date(21, 0, 0))
        )
    }

    func testReturnsNilWhenNoDaysConfigured() {
        let now = date(19, 10, 0)
        XCTAssertNil(JourneySchedule.nextJourneyDate(now: now, config: config(days: [])))
    }

    // MARK: - Upcoming leg

    func testUpcomingLegIsOutboundBeforeDeparture() {
        let now = date(19, 7, 0)
        let times = JourneySchedule.legTimes(on: date(19, 0, 0), config: config())
        XCTAssertEqual(JourneySchedule.upcomingLeg(now: now, outbound: times.outbound, returnLeg: times.return), .outbound)
    }

    func testUpcomingLegIsReturnAfterDeparture() {
        let now = date(19, 12, 0)
        let times = JourneySchedule.legTimes(on: date(19, 0, 0), config: config())
        XCTAssertEqual(JourneySchedule.upcomingLeg(now: now, outbound: times.outbound, returnLeg: times.return), .returnLeg)
    }

    // MARK: - Leg times

    func testLegTimesUseConfiguredMinutes() {
        let times = JourneySchedule.legTimes(on: date(19, 0, 0), config: config())
        XCTAssertEqual(times.outbound, date(19, 8, 11))
        XCTAssertEqual(times.return, date(19, 18, 13))
    }
}
