import Foundation

/// Which leg of the journey is next.
enum LegKind: Equatable {
    case outbound
    case returnLeg
}

/// Pure, deterministic journey scheduling in the Europe/Amsterdam time zone.
enum JourneySchedule {
    /// Calendar used for all journey math: Amsterdam time, Gregorian, POSIX locale.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// The journey date to show:
    /// - today, while `now` is at or before today's return time;
    /// - otherwise the next configured day (e.g. Monday after a weekend).
    /// Returns nil when no days are configured.
    static func nextJourneyDate(
        now: Date,
        config: JourneyConfig,
        calendar: Calendar = calendar
    ) -> Date? {
        guard !config.days.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        for offset in 0..<7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = Weekday.of(candidate, calendar: calendar)
            guard config.days.contains(weekday) else { continue }
            if offset == 0 {
                let returnTime = config.time(of: config.returnMinutes, on: candidate, calendar: calendar)
                if now <= returnTime { return candidate }
                continue
            }
            return candidate
        }
        return nil
    }

    /// Absolute departure times of both legs on the given journey date.
    static func legTimes(
        on date: Date,
        config: JourneyConfig,
        calendar: Calendar = calendar
    ) -> (outbound: Date, return: Date) {
        (
            config.time(of: config.departMinutes, on: date, calendar: calendar),
            config.time(of: config.returnMinutes, on: date, calendar: calendar)
        )
    }

    /// The next leg of an active journey.
    static func upcomingLeg(now: Date, outbound: Date, returnLeg: Date) -> LegKind {
        if now < outbound { return .outbound }
        if now < returnLeg { return .returnLeg }
        return .outbound
    }
}
