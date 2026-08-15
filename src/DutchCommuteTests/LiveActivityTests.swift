import XCTest
@testable import DutchCommute

final class LiveActivityTests: XCTestCase {
    private let utrecht = Station(code: "UT", name: "Utrecht Centraal")
    private let amsterdam = Station(code: "ASD", name: "Amsterdam Centraal")
    private let busStop = Station(code: "BUS1", name: "Busplein")

    private var trainChoices: [StationChoice] {
        [
            StationChoice(id: "UT", name: "Utrecht Centraal", mode: .train),
            StationChoice(id: "ASD", name: "Amsterdam Centraal", mode: .train),
            StationChoice(id: "BUS1", name: "Busplein", mode: .bus),
        ]
    }

    /// Monday 2026-08-10 07:00 (Amsterdam): a weekday morning, so the
    /// journey date is today and the outbound leg (08:00) is upcoming.
    private var now: Date {
        JourneySchedule.calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 7))!
    }

    private func journey(
        from: Station,
        to: Station,
        isActive: Bool = true,
        showsLiveActivity: Bool = true,
        showsNearDeparture: Bool = false
    ) -> JourneyConfig {
        JourneyConfig(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_000),
            from: from,
            to: to,
            departMinutes: 8 * 60,
            returnMinutes: 18 * 60,
            days: [.monday, .tuesday, .wednesday, .thursday, .friday],
            isActive: isActive,
            showsLiveActivity: showsLiveActivity,
            showsNearDeparture: showsNearDeparture
        )
    }

    private func legTimes(for config: JourneyConfig, now: Date) -> (outbound: Date, return: Date) {
        let journeyDate = JourneySchedule.nextJourneyDate(now: now, config: config)!
        return JourneySchedule.legTimes(on: journeyDate, config: config)
    }

    // MARK: - JourneyConfig persistence

    func testJourneyConfigLiveActivitySettingsDefaultOff() throws {
        let json = #"{"id":"11111111-1111-1111-1111-111111111111","createdAt":0,"from":{"code":"UT","name":"Utrecht Centraal"},"to":{"code":"ASD","name":"Amsterdam Centraal"},"departMinutes":480,"returnMinutes":1080,"days":[1,2]}"#
        let decoded = try JSONDecoder().decode(JourneyConfig.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.showsLiveActivity)
        XCTAssertFalse(decoded.showsNearDeparture)
    }

    func testJourneyConfigLiveActivitySettingsRoundTrip() throws {
        let config = journey(from: utrecht, to: amsterdam, showsLiveActivity: true, showsNearDeparture: true)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(JourneyConfig.self, from: data)
        XCTAssertTrue(decoded.showsLiveActivity)
        XCTAssertTrue(decoded.showsNearDeparture)
    }

    // MARK: - Eligibility

    func testEligibleWhenBothStopsAreTrainStations() {
        XCTAssertTrue(LiveActivityManager.isEligible(journey(from: utrecht, to: amsterdam), choices: trainChoices))
    }

    func testNotEligibleWhenEitherStopIsNotATrainStation() {
        XCTAssertFalse(LiveActivityManager.isEligible(journey(from: utrecht, to: busStop), choices: trainChoices))
        XCTAssertFalse(LiveActivityManager.isEligible(journey(from: busStop, to: amsterdam), choices: trainChoices))
        XCTAssertFalse(LiveActivityManager.isEligible(journey(from: busStop, to: busStop), choices: trainChoices))
    }

    func testNotEligibleWhenStopsAreUnknown() {
        let unknown = Station(code: "ZZZ", name: "Ergens")
        XCTAssertFalse(LiveActivityManager.isEligible(journey(from: unknown, to: amsterdam), choices: trainChoices))
    }

    // MARK: - Decision

    func testInactiveJourneyNeverRuns() {
        let config = journey(from: utrecht, to: amsterdam, isActive: false)
        XCTAssertEqual(LiveActivityManager.decision(for: config, choices: trainChoices, now: now), .none)
    }

    func testDisabledLiveActivityNeverRuns() {
        let config = journey(from: utrecht, to: amsterdam, showsLiveActivity: false)
        XCTAssertEqual(LiveActivityManager.decision(for: config, choices: trainChoices, now: now), .none)
    }

    func testIneligibleJourneyNeverRuns() {
        let config = journey(from: utrecht, to: busStop)
        XCTAssertEqual(LiveActivityManager.decision(for: config, choices: trainChoices, now: now), .none)
    }

    func testNoJourneyDateNeverRuns() {
        var config = journey(from: utrecht, to: amsterdam)
        config.days = []
        XCTAssertEqual(LiveActivityManager.decision(for: config, choices: trainChoices, now: now), .none)
    }

    func testFullModeRunsForTheWholeJourneyPeriod() {
        let config = journey(from: utrecht, to: amsterdam)
        let times = legTimes(for: config, now: now)
        guard case .run(let start, let end, let leg) = LiveActivityManager.decision(for: config, choices: trainChoices, now: now) else {
            return XCTFail("expected run")
        }
        XCTAssertEqual(start, times.outbound)
        XCTAssertEqual(end, times.return)
        XCTAssertEqual(leg, .outbound)
    }

    func testNearDepartureWaitsUntilOneHourBeforeDeparture() {
        let config = journey(from: utrecht, to: amsterdam, showsNearDeparture: true)
        let times = legTimes(for: config, now: now)
        // 06:00 Amsterdam — one hour before the 07:00 window start.
        let early = JourneySchedule.calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 6))!
        XCTAssertEqual(
            LiveActivityManager.decision(for: config, choices: trainChoices, now: early),
            .waitUntil(times.outbound.addingTimeInterval(-3600))
        )
    }

    func testNearDepartureRunsWithinTheWindow() {
        let config = journey(from: utrecht, to: amsterdam, showsNearDeparture: true)
        let times = legTimes(for: config, now: now)
        let inWindow = times.outbound.addingTimeInterval(-1800)
        guard case .run(let start, let end, _) = LiveActivityManager.decision(for: config, choices: trainChoices, now: inWindow) else {
            return XCTFail("expected run")
        }
        XCTAssertEqual(start, times.outbound)
        XCTAssertEqual(end, times.return)
    }

    func testOnlyTheActiveJourneyRuns() {
        let active = journey(from: utrecht, to: amsterdam, isActive: true)
        let other = journey(from: utrecht, to: amsterdam, isActive: false, showsLiveActivity: true)
        let decisions = [active, other].map { LiveActivityManager.decision(for: $0, choices: trainChoices, now: now) }
        guard case .run = decisions[0] else { return XCTFail("active journey should run") }
        XCTAssertEqual(decisions[1], .none)
    }

    // MARK: - Toggle state behavior (AppState)

    func testTogglingLiveActivityOffClearsNearDeparture() throws {
        let store = ConfigStore(defaults: UserDefaults(suiteName: "live-activity-tests-\(UUID().uuidString)")!)
        let state = AppState(store: store)
        var config = journey(from: utrecht, to: amsterdam)
        config.isActive = true
        state.addJourney(config)

        state.setShowsLiveActivity(config.id, shows: true)
        state.setShowsNearDeparture(config.id, shows: true)
        XCTAssertTrue(state.journeys[0].showsLiveActivity)
        XCTAssertTrue(state.journeys[0].showsNearDeparture)

        state.setShowsLiveActivity(config.id, shows: false)
        XCTAssertFalse(state.journeys[0].showsLiveActivity)
        XCTAssertFalse(state.journeys[0].showsNearDeparture)

        // Persisted in the shared store.
        XCTAssertEqual(store.load().first?.showsLiveActivity, false)
        XCTAssertEqual(store.load().first?.showsNearDeparture, false)
    }

    // MARK: - Cancellation and stale data

    func testStatusDisplayMapsCancellation() {
        XCTAssertEqual(LiveActivityManager.statusDisplay(for: .onTime).label, "On time")
        XCTAssertFalse(LiveActivityManager.statusDisplay(for: .onTime).isCancelled)
        XCTAssertEqual(LiveActivityManager.statusDisplay(for: .cancelled).label, "Cancelled")
        XCTAssertTrue(LiveActivityManager.statusDisplay(for: .cancelled).isCancelled)
        XCTAssertEqual(LiveActivityManager.statusDisplay(for: .delayed(minutes: 5)).label, "+5 min")
        XCTAssertFalse(LiveActivityManager.statusDisplay(for: .delayed(minutes: 5)).isCancelled)
    }

    func testStaleDateIsFiveMinutesAfterRefresh() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(LiveActivityManager.staleDate(now: now), now.addingTimeInterval(5 * 60))
    }
}
