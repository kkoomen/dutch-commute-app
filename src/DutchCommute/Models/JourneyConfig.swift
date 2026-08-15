import Foundation

/// Day of the week, with Monday = 1 (matches how the UI presents days).
enum Weekday: Int, CaseIterable, Identifiable, Codable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .monday: String(localized: "Mon")
        case .tuesday: String(localized: "Tue")
        case .wednesday: String(localized: "Wed")
        case .thursday: String(localized: "Thu")
        case .friday: String(localized: "Fri")
        case .saturday: String(localized: "Sat")
        case .sunday: String(localized: "Sun")
        }
    }

    /// Gregorian calendar weekday number (Sunday = 1 ... Saturday = 7).
    var calendarValue: Int { rawValue == 7 ? 1 : rawValue + 1 }

    static func of(_ date: Date, calendar: Calendar) -> Weekday {
        let value = calendar.component(.weekday, from: date)
        return Weekday(rawValue: value == 1 ? 7 : value - 1)!
    }
}

/// A user journey: route (with optional via), transport mode, departure/
/// return times, and active days.
struct JourneyConfig: Codable, Equatable, Identifiable {
    var id: UUID
    /// Absolute creation time (persisted; used for ordering).
    var createdAt: Date
    var from: Station
    var to: Station
    /// Minutes since midnight (Europe/Amsterdam) for the outbound departure.
    var departMinutes: Int
    /// Minutes since midnight (Europe/Amsterdam) for the return departure.
    var returnMinutes: Int
    var days: Set<Weekday>
    /// Whether this journey is the one shown on the Lock Screen widget;
    /// at most one journey is active.
    var isActive: Bool = false
    /// Whether a Live Activity should be started for this journey
    /// (only possible between two train stations).
    var showsLiveActivity: Bool = false
    /// Whether the Live Activity should only appear from one hour before
    /// departure (instead of the full journey period).
    var showsNearDeparture: Bool = false

    /// Absolute time of `minutes` on the given day, in the Amsterdam calendar.
    func time(of minutes: Int, on date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .minute, value: minutes, to: start)!
    }
}

extension JourneyConfig {
    private enum CodingKeys: String, CodingKey {
        case id, createdAt, from, to, departMinutes, returnMinutes, days, isActive, showsLiveActivity, showsNearDeparture
    }

    /// Tolerates configs persisted before `via` existed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        from = try c.decode(Station.self, forKey: .from)
        to = try c.decode(Station.self, forKey: .to)
        departMinutes = try c.decode(Int.self, forKey: .departMinutes)
        returnMinutes = try c.decode(Int.self, forKey: .returnMinutes)
        days = try c.decode(Set<Weekday>.self, forKey: .days)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        showsLiveActivity = try c.decodeIfPresent(Bool.self, forKey: .showsLiveActivity) ?? false
        showsNearDeparture = try c.decodeIfPresent(Bool.self, forKey: .showsNearDeparture) ?? false
    }
}
