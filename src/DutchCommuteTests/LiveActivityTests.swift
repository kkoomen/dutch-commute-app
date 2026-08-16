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

    /// `isActive` (the Lock Screen widget choice) must not influence the
    /// Live Activity decision: the activity follows `showsLiveActivity`
    /// alone, so the same journey decides identically whether it is the
    /// active one or not.
    func testLiveActivityDecisionIgnoresIsActive() {
        let active = journey(from: utrecht, to: amsterdam, isActive: true)
        let inactive = journey(from: utrecht, to: amsterdam, isActive: false)
        XCTAssertEqual(
            LiveActivityManager.decision(for: active, choices: trainChoices, now: now),
            LiveActivityManager.decision(for: inactive, choices: trainChoices, now: now)
        )
        guard case .run = LiveActivityManager.decision(for: inactive, choices: trainChoices, now: now) else {
            return XCTFail("live activity should not require lock screen activation")
        }
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

    func testNonActiveJourneyCanRunLiveActivity() {
        let config = journey(from: utrecht, to: amsterdam, isActive: false, showsLiveActivity: true)
        guard case .run = LiveActivityManager.decision(for: config, choices: trainChoices, now: now) else {
            return XCTFail("live activity should not require lock screen activation")
        }
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

    /// Enabling "Show live activity" must not change the Lock Screen journey.
    func testEnablingLiveActivityDoesNotChangeJourneyActiveState() throws {
        let store = ConfigStore(defaults: UserDefaults(suiteName: "live-activity-tests-\(UUID().uuidString)")!)
        let state = AppState(store: store)
        var other = journey(from: utrecht, to: amsterdam, isActive: true)
        other.showsLiveActivity = false
        state.addJourney(other)
        var config = journey(from: utrecht, to: amsterdam, isActive: false)
        config.showsLiveActivity = false
        state.addJourney(config)

        state.setShowsLiveActivity(config.id, shows: true)

        XCTAssertTrue(state.journeys.first(where: { $0.id == config.id })?.showsLiveActivity == true)
        XCTAssertFalse(state.journeys.first(where: { $0.id == config.id })?.isActive == true)
        XCTAssertTrue(state.journeys.first(where: { $0.id == other.id })?.isActive == true)
        XCTAssertFalse(state.journeys.first(where: { $0.id == other.id })?.showsLiveActivity == true)

        // Persisted in the shared store.
        XCTAssertEqual(store.load().first(where: { $0.id == config.id })?.isActive, false)
        XCTAssertEqual(store.load().first(where: { $0.id == other.id })?.isActive, true)
    }

    func testEnablingLiveActivityDisablesItForOtherJourneys() throws {
        let store = ConfigStore(defaults: UserDefaults(suiteName: "live-activity-tests-\(UUID().uuidString)")!)
        let state = AppState(store: store)
        var first = journey(from: utrecht, to: amsterdam, isActive: true)
        first.showsLiveActivity = true
        state.addJourney(first)
        let second = journey(from: utrecht, to: amsterdam, isActive: false)
        state.addJourney(second)

        state.setShowsLiveActivity(second.id, shows: true)

        XCTAssertFalse(state.journeys.first(where: { $0.id == first.id })?.showsLiveActivity == true)
        XCTAssertTrue(state.journeys.first(where: { $0.id == second.id })?.showsLiveActivity == true)
    }

    /// Turning the activity off must not change the active-journey state.
    func testDisablingLiveActivityKeepsJourneyActive() throws {
        let store = ConfigStore(defaults: UserDefaults(suiteName: "live-activity-tests-\(UUID().uuidString)")!)
        let state = AppState(store: store)
        var config = journey(from: utrecht, to: amsterdam, isActive: true)
        config.showsLiveActivity = false
        state.addJourney(config)

        state.setShowsLiveActivity(config.id, shows: false)

        XCTAssertFalse(state.journeys[0].showsLiveActivity)
        XCTAssertTrue(state.journeys[0].isActive)
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

    func testStatusKindMapsTrainStatus() {
        XCTAssertEqual(LiveActivityManager.kind(for: .onTime), .onTime)
        XCTAssertEqual(LiveActivityManager.kind(for: .delayed(minutes: 5)), .delayed)
        XCTAssertEqual(LiveActivityManager.kind(for: .cancelled), .cancelled)
        XCTAssertEqual(LiveActivityManager.kind(for: .unknown), .unknown)
    }

    func testStaleDateIsFiveMinutesAfterRefresh() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(LiveActivityManager.staleDate(now: now), now.addingTimeInterval(5 * 60))
    }

    func testRefreshIntervalIsOneMinute() {
        XCTAssertEqual(LiveActivityManager.refreshInterval, 60)
    }

    // MARK: - Content state (push contract)

    func testContentStateRoundTripsWithRouteName() throws {
        let state = JourneyActivityAttributes.ContentState(
            routeName: "IC 1234",
            fromName: "Utrecht Centraal",
            toName: "Amsterdam Centraal",
            track: "4",
            departureTime: Date(timeIntervalSince1970: 1_720_000_000),
            status: "+5 min",
            isCancelled: false,
            statusKind: .delayed,
            lastUpdate: Date(timeIntervalSince1970: 1_720_000_000),
            isStale: false
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(JourneyActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func testContentStateDecodesWithoutTrack() throws {
        // States pushed before a track was known (or from a backend that
        // omits it) must decode: track stays nil, route still renders.
        let json = """
        {\"routeName\":\"IC 1234\",\"fromName\":\"Utrecht Centraal\",\"toName\":\"Amsterdam Centraal\",
         \"departureTime\":1720000000,\"status\":\"On time\",\"isCancelled\":false,\"isStale\":false}
        """
        let decoded = try JSONDecoder().decode(JourneyActivityAttributes.ContentState.self, from: Data(json.utf8))
        XCTAssertNil(decoded.track)
        // Payloads that predate statusKind decode with nil (unknown).
        XCTAssertNil(decoded.statusKind)
        XCTAssertEqual(decoded.fromName, "Utrecht Centraal")
        XCTAssertEqual(decoded.toName, "Amsterdam Centraal")
    }
}
