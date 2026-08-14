import Foundation
import Observation
import WidgetKit

/// Shared app state: journey config, station list, API client.
@Observable
final class AppState {
    let client: NSAPIClient
    private let store: ConfigStore

    var config: JourneyConfig?
    var isEditing = false
    var stations: [Station] = []
    private(set) var stationsLoaded = false
    var stationsErrorMessage: String?

    init(client: NSAPIClient = NSAPIClient(apiKey: APIKey.ns), store: ConfigStore = ConfigStore()) {
        self.client = client
        self.store = store
        self.config = store.load()
    }

    func save(_ config: JourneyConfig) {
        store.save(config)
        self.config = config
        isEditing = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    func startEditing() {
        isEditing = true
    }

    func cancelEditing() {
        isEditing = false
    }

    /// Loads the station list once for autocomplete.
    func loadStations() async {
        guard !stationsLoaded else { return }
        do {
            stations = try await client.fetchStations()
            stationsLoaded = true
            stationsErrorMessage = nil
        } catch {
            stationsErrorMessage = error.localizedDescription
        }
    }
}
