import Foundation

/// App Group shared by the app and the widget extension.
enum AppGroup {
    static let identifier = "group.com.travelscreen.app"
}

/// Persists the journey configuration in shared UserDefaults
/// (visible to both the app and the widget extension).
struct ConfigStore {
    private let key = "journeyConfig"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard) {
        self.defaults = defaults
    }

    func load() -> JourneyConfig? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(JourneyConfig.self, from: data)
    }

    func save(_ config: JourneyConfig) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: key)
        }
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
