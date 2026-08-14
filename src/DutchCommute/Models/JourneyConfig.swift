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

/// Transport modes for a journey. Multiple can be selected; at least one
/// is always required. Defaults to all modes.
enum TransportMode: String, CaseIterable, Identifiable, Codable {
    case train, bus, metro, tram, ferry

    var id: String { rawValue }

    /// Display name, e.g. "Train".
    var label: String {
        switch self {
        case .train: String(localized: "Train")
        case .bus: String(localized: "Bus")
        case .metro: String(localized: "Metro")
        case .tram: String(localized: "Tram")
        case .ferry: String(localized: "Ferry")
        }
    }

    /// SF Symbol for the mode tile.
    var icon: String {
        switch self {
        case .train: "train.side.front.car"
        case .bus: "bus.fill"
        case .metro: "tram.fill.tunnel"
        case .tram: "tram.fill"
        case .ferry: "ferry.fill"
        }
    }

    /// API modality code, e.g. "TRAIN".
    var apiCode: String { rawValue.uppercased() }

    /// Modality codes to disable so that only `selected` modes remain,
    /// e.g. "BUS,FERRY,TRAM,METRO" when only `.train` is selected;
    /// empty when every mode is selected (then the API default applies
    /// and the parameter is omitted).
    static func disabledModalityCodes(keeping selected: Set<TransportMode>) -> String {
        allCases.filter { !selected.contains($0) }.map(\.apiCode).joined(separator: ",")
    }
}

/// A user journey: route (with optional via), transport mode, departure/
/// return times, and active days.
struct JourneyConfig: Codable, Equatable, Identifiable {
    var id: UUID
    /// Absolute creation time — shown on the "My journeys" list.
    var createdAt: Date
    var from: Station
    /// Optional intermediate station for the trip.
    var via: Station? = nil
    var to: Station
    /// Minutes since midnight (Europe/Amsterdam) for the outbound departure.
    var departMinutes: Int
    /// Minutes since midnight (Europe/Amsterdam) for the return departure.
    var returnMinutes: Int
    var days: Set<Weekday>
    /// How the user travels; all modes selected by default, at least one
    /// required.
    var transportModes: Set<TransportMode> = Set(TransportMode.allCases)

    /// Absolute time of `minutes` on the given day, in the Amsterdam calendar.
    func time(of minutes: Int, on date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .minute, value: minutes, to: start)!
    }
}

extension JourneyConfig {
    private enum CodingKeys: String, CodingKey {
        case id, createdAt, from, via, to, departMinutes, returnMinutes, days, transportModes
    }

    /// Legacy key: configs saved when a single `transportMode` was stored.
    private enum LegacyCodingKeys: String, CodingKey {
        case transportMode
    }

    /// Tolerates configs persisted before `via` and `transportModes` existed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        from = try c.decode(Station.self, forKey: .from)
        via = try c.decodeIfPresent(Station.self, forKey: .via)
        to = try c.decode(Station.self, forKey: .to)
        departMinutes = try c.decode(Int.self, forKey: .departMinutes)
        returnMinutes = try c.decode(Int.self, forKey: .returnMinutes)
        days = try c.decode(Set<Weekday>.self, forKey: .days)
        if let modes = try c.decodeIfPresent(Set<TransportMode>.self, forKey: .transportModes) {
            transportModes = modes
        } else if let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            .decodeIfPresent(TransportMode.self, forKey: .transportMode) {
            transportModes = [legacy]
        } else {
            transportModes = Set(TransportMode.allCases)
        }
    }
}
