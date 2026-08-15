import ActivityKit
import Foundation

/// Starts, updates and ends the journey Live Activity.
///
/// Rules:
/// - Only the **active** journey may run an activity.
/// - `showsLiveActivity` off → never start; any existing activity ends.
/// - Both endpoints must be train stations (see `isEligible`).
/// - `showsNearDeparture` on → the activity only runs from one hour
///   before the next departure until the journey ends; off → the full
///   journey period.
/// - The activity ends when the journey ends, when it is deleted,
///   deactivated, disabled, or when the train is cancelled.
enum LiveActivityManager {
    enum Decision: Equatable {
        /// Inactive, disabled, ineligible, or no journey date.
        case none
        /// Near-departure mode: start the activity at this date.
        case waitUntil(Date)
        /// Run from `start` to `end` (the journey's return departure).
        case run(start: Date, end: Date, leg: LegKind)
    }

    /// A stop is a train station when the picker data says so; stops that
    /// are unknown (or GTFS bus/metro/tram stops) are not eligible.
    static func isEligible(_ journey: JourneyConfig, choices: [StationChoice]) -> Bool {
        func isTrain(_ station: Station) -> Bool {
            guard let choice = choices.first(where: { $0.id == station.code }) else { return false }
            return choice.mode == .train
        }
        return isTrain(journey.from) && isTrain(journey.to)
    }

    /// The pure decision for a journey at `now`.
    static func decision(
        for journey: JourneyConfig,
        choices: [StationChoice],
        now: Date,
        calendar: Calendar = JourneySchedule.calendar
    ) -> Decision {
        guard journey.isActive, journey.showsLiveActivity, isEligible(journey, choices: choices) else {
            return .none
        }
        guard let journeyDate = JourneySchedule.nextJourneyDate(now: now, config: journey, calendar: calendar) else {
            return .none
        }
        let times = JourneySchedule.legTimes(on: journeyDate, config: journey, calendar: calendar)
        let leg = JourneySchedule.upcomingLeg(now: now, outbound: times.outbound, returnLeg: times.return)
        let departure = leg == .outbound ? times.outbound : times.return
        let end = times.return

        if journey.showsNearDeparture {
            let windowStart = departure.addingTimeInterval(-3600)
            if now < windowStart {
                return .waitUntil(windowStart)
            }
        }
        return .run(start: departure, end: end, leg: leg)
    }

    /// The activity's status text and cancellation flag for a leg.
    static func statusDisplay(for status: TrainStatus) -> (label: String, isCancelled: Bool) {
        (status.label, status == .cancelled)
    }

    /// Stale date for activity content: shortly after the refresh, so the
    /// system flags the activity as stale when updates stop arriving.
    static func staleDate(now: Date) -> Date {
        now.addingTimeInterval(5 * 60)
    }

    // MARK: - ActivityKit

    private static var pushTokenTasks: [String: Task<Void, Never>] = [:]
    private static var endTasks: [String: Task<Void, Never>] = [:]
    private static let updateClient: LiveActivityUpdateClient = NoopLiveActivityUpdateClient()

    /// Reconciles running activities with the current journeys.
    static func apply(
        journeys: [JourneyConfig],
        choices: [StationChoice],
        now: Date = Date(),
        calendar: Calendar = JourneySchedule.calendar
    ) async {
        let activeID = journeys.first(where: \.isActive)?.id

        // End everything that should not exist.
        for activity in Activity<JourneyActivityAttributes>.activities {
            if activity.attributes.journeyID != activeID {
                await end(activity, tokenStoreDelete: true)
            }
        }

        guard let active = journeys.first(where: \.isActive) else { return }
        switch decision(for: active, choices: choices, now: now, calendar: calendar) {
        case .none:
            if let activity = activity(for: active.id) {
                await end(activity, tokenStoreDelete: true)
            }
        case .waitUntil(let start):
            if let activity = activity(for: active.id) {
                await end(activity, tokenStoreDelete: true)
            }
            scheduleStart(at: start, journeys: journeys, choices: choices)
        case .run(let startDate, let endDate, let leg):
            if let activity = activity(for: active.id) {
                await refresh(activity, journey: active, leg: leg, at: startDate, now: now)
            } else {
                await start(activity: active, leg: leg, at: startDate, now: now)
            }
            scheduleEnd(at: endDate, journeyID: active.id)
        }
    }

    /// Ends every running activity (e.g. on logout/first launch cleanup).
    static func endAll() async {
        for activity in Activity<JourneyActivityAttributes>.activities {
            await end(activity, tokenStoreDelete: true)
        }
    }

    // MARK: - Start / update / end

    private static func start(activity journey: JourneyConfig, leg: LegKind, at departure: Date, now: Date) async {
        // Fetch the leg's train so the attributes carry the route name.
        let from = leg == .outbound ? journey.from : journey.to
        let to = leg == .outbound ? journey.to : journey.from
        let legInfo = await fetchLeg(from: from, to: to, at: departure)

        let attributes = JourneyActivityAttributes(
            journeyID: journey.id,
            routeName: legInfo.routeName,
            fromName: journey.from.name,
            toName: journey.to.name,
            destination: legInfo.destination,
            scheduledDeparture: departure
        )
        let initialState = JourneyActivityAttributes.ContentState(
            departureTime: legInfo.displayedDeparture,
            status: legInfo.status,
            isCancelled: legInfo.isCancelled,
            lastUpdate: now,
            isStale: legInfo.isStale
        )
        let content = ActivityContent(state: initialState, staleDate: Self.staleDate(now: now))

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: .token
            )
            observePushTokens(activity)
            if legInfo.isCancelled {
                // Show the cancellation briefly, then end.
                await end(activity, tokenStoreDelete: true, after: 2 * 60)
            }
        } catch {
            // Starting failed (e.g. permission denied or budget) — nothing to do.
        }
    }

    private static func refresh(
        _ activity: Activity<JourneyActivityAttributes>,
        journey: JourneyConfig,
        leg: LegKind,
        at departure: Date,
        now: Date
    ) async {
        let from = leg == .outbound ? journey.from : journey.to
        let to = leg == .outbound ? journey.to : journey.from
        let legInfo = await fetchLeg(from: from, to: to, at: departure)

        let state = JourneyActivityAttributes.ContentState(
            departureTime: legInfo.displayedDeparture,
            status: legInfo.status,
            isCancelled: legInfo.isCancelled,
            lastUpdate: now,
            isStale: legInfo.isStale
        )
        let content = ActivityContent(state: state, staleDate: Self.staleDate(now: now))
        await activity.update(content)

        if legInfo.isCancelled {
            await end(activity, tokenStoreDelete: true, after: 2 * 60)
        }
    }

    private static func end(
        _ activity: Activity<JourneyActivityAttributes>,
        tokenStoreDelete: Bool,
        after delay: TimeInterval? = nil
    ) async {
        let activityID = activity.id
        let dismissal: ActivityUIDismissalPolicy = delay.map { .after(Date().addingTimeInterval($0)) } ?? .immediate
        if tokenStoreDelete {
            LiveActivityPushTokenStore.delete(for: activityID)
            await updateClient.unregister(activityID: activityID)
        }
        pushTokenTasks[activityID]?.cancel()
        pushTokenTasks[activityID] = nil
        await activity.end(nil, dismissalPolicy: dismissal)
    }

    // MARK: - Scheduling (runs while the app process is alive)

    private static func scheduleStart(at date: Date, journeys: [JourneyConfig], choices: [StationChoice]) {
        Task {
            try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            await apply(journeys: journeys, choices: choices, now: Date())
        }
    }

    private static func scheduleEnd(at date: Date, journeyID: UUID) {
        endTasks[journeyID.uuidString]?.cancel()
        endTasks[journeyID.uuidString] = Task {
            try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            if let activity = activity(for: journeyID) {
                await end(activity, tokenStoreDelete: true)
            }
        }
    }

    // MARK: - Helpers

    private static func activity(for journeyID: UUID) -> Activity<JourneyActivityAttributes>? {
        Activity<JourneyActivityAttributes>.activities.first { $0.attributes.journeyID == journeyID }
    }

    private static func observePushTokens(_ activity: Activity<JourneyActivityAttributes>) {
        let activityID = activity.id
        pushTokenTasks[activityID]?.cancel()
        pushTokenTasks[activityID] = Task {
            for await token in activity.pushTokenUpdates {
                LiveActivityPushTokenStore.save(token, for: activityID)
                await updateClient.register(
                    pushToken: token,
                    for: activityID,
                    journeyID: activity.attributes.journeyID
                )
            }
        }
    }

    /// Best-effort live data for the leg; always returns something so the
    /// activity can render scheduled data when the fetch fails (marked
    /// stale).
    private static func fetchLeg(from: Station, to: Station, at date: Date) async -> LegInfo {
        do {
            let trip = try await NSAPIClient(apiKey: APIKey.ns).fetchTrip(from: from, to: to, at: date)
            guard let leg = trip.firstLeg.flatMap(TrainLeg.init) else {
                return LegInfo(routeName: String(localized: "Train"), destination: to.name,
                               displayedDeparture: date, status: String(localized: "Unknown"),
                               isCancelled: false, isStale: true)
            }
            return LegInfo(
                routeName: leg.name,
                destination: leg.direction.isEmpty ? to.name : leg.direction,
                displayedDeparture: leg.displayedDeparture,
                status: statusDisplay(for: leg.status).label,
                isCancelled: statusDisplay(for: leg.status).isCancelled,
                isStale: false
            )
        } catch {
            return LegInfo(routeName: String(localized: "Train"), destination: to.name,
                           displayedDeparture: date, status: String(localized: "Unknown"),
                           isCancelled: false, isStale: true)
        }
    }

    private struct LegInfo {
        let routeName: String
        let destination: String
        let displayedDeparture: Date
        let status: String
        let isCancelled: Bool
        let isStale: Bool
    }
}
