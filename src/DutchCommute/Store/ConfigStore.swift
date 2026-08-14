import Foundation

/// App Group shared by the app and the widget extension.
enum AppGroup {
    static let identifier = "group.com.dutchcommute.app"
}

/// Persists all journeys in shared UserDefaults
/// (visible to both the app and the widget extension).
/// Order is the user's order: newest-first by creation time until the user
/// manually reorders via drag.
struct ConfigStore {
    private let key = "journeys"
    private let legacyKey = "journeyConfig"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard) {
        self.defaults = defaults
    }

    func load() -> [JourneyConfig] {
        if let data = defaults.data(forKey: key),
           let journeys = try? JSONDecoder().decode([JourneyConfig].self, from: data) {
            return journeys
        }
        return migrateLegacyConfig()
    }

    func save(_ journeys: [JourneyConfig]) {
        if let data = try? JSONEncoder().encode(journeys) {
            defaults.set(data, forKey: key)
        }
    }

    /// One-time migration from the pre-multi-journey single config.
    private func migrateLegacyConfig() -> [JourneyConfig] {
        guard let data = defaults.data(forKey: legacyKey),
              let legacy = try? JSONDecoder().decode(LegacyJourney.self, from: data)
        else { return [] }
        let journey = JourneyConfig(
            id: UUID(),
            createdAt: Date(),
            from: legacy.from,
            to: legacy.to,
            departMinutes: legacy.departMinutes,
            returnMinutes: legacy.returnMinutes,
            days: legacy.days
        )
        save([journey])
        defaults.removeObject(forKey: legacyKey)
        return [journey]
    }

    /// The old single-config shape, for migration only.
    private struct LegacyJourney: Codable {
        var from: Station
        var to: Station
        var departMinutes: Int
        var returnMinutes: Int
        var days: Set<Weekday>
    }
}
