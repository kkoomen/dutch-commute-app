import Foundation

/// Day of the week, with Monday = 1 (matches how the UI presents days).
enum Weekday: Int, CaseIterable, Identifiable, Codable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    var shortName: String {
        ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][rawValue - 1]
    }

    /// Gregorian calendar weekday number (Sunday = 1 ... Saturday = 7).
    var calendarValue: Int { rawValue == 7 ? 1 : rawValue + 1 }

    static func of(_ date: Date, calendar: Calendar) -> Weekday {
        let value = calendar.component(.weekday, from: date)
        return Weekday(rawValue: value == 1 ? 7 : value - 1)!
    }
}

/// The user's daily journey: route, departure/return times, and active days.
struct JourneyConfig: Codable, Equatable {
    var from: Station
    var to: Station
    /// Minutes since midnight (Europe/Amsterdam) for the outbound departure.
    var departMinutes: Int
    /// Minutes since midnight (Europe/Amsterdam) for the return departure.
    var returnMinutes: Int
    var days: Set<Weekday>

    /// Absolute time of `minutes` on the given day, in the Amsterdam calendar.
    func time(of minutes: Int, on date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .minute, value: minutes, to: start)!
    }
}
