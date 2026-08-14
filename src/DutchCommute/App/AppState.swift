import Foundation
import Observation
import WidgetKit

/// Navigation routes pushed on the root NavigationStack.
enum JourneyRoute: Hashable {
    case journey(UUID)
    case setup(UUID?) // nil = new journey
}

/// Shared app state: journeys, navigation, station list, API client.
@Observable
final class AppState {
    let client: NSAPIClient
    private let store: ConfigStore

    /// User-ordered journeys (newest-first until manually reordered).
    var journeys: [JourneyConfig] = []
    var path: [JourneyRoute] = []
    var stations: [Station] = []
    private(set) var stationsLoaded = false
    var stationsErrorMessage: String?
    /// Recently picked stations, shared between the From and To pickers.
    var stationHistory: [Station] = []

    private let stationHistoryKey = "stationHistory"

    init(client: NSAPIClient = NSAPIClient(apiKey: APIKey.ns), store: ConfigStore = ConfigStore()) {
        self.client = client
        self.store = store
        self.journeys = store.load()
        if let data = UserDefaults.standard.data(forKey: stationHistoryKey),
           let decoded = try? JSONDecoder().decode([Station].self, from: data) {
            stationHistory = decoded
        }
    }

    /// Records a picked station at the top of the shared history (capped
    /// at 10 entries) and persists it.
    func addToStationHistory(_ station: Station) {
        stationHistory.removeAll { $0 == station }
        stationHistory.insert(station, at: 0)
        if stationHistory.count > 10 {
            stationHistory = Array(stationHistory.prefix(10))
        }
        if let data = try? JSONEncoder().encode(stationHistory) {
            UserDefaults.standard.set(data, forKey: stationHistoryKey)
        }
    }

    func addJourney(_ journey: JourneyConfig) {
        journeys.insert(journey, at: 0)
        persistAndReloadWidgets()
    }

    func updateJourney(_ journey: JourneyConfig) {
        guard let index = journeys.firstIndex(where: { $0.id == journey.id }) else { return }
        journeys[index] = journey
        persistAndReloadWidgets()
    }

    func deleteJourneys(at offsets: IndexSet) {
        journeys.remove(atOffsets: offsets)
        persistAndReloadWidgets()
    }

    /// Deletes one journey by id (after user confirmation in the UI).
    func deleteJourney(_ id: UUID) {
        journeys.removeAll { $0.id == id }
        persistAndReloadWidgets()
    }

    /// Marks one journey as active — the one shown on the Lock Screen.
    /// Only one journey can be active, so activating one deactivates all
    /// others; `active: false` just deactivates it.
    func setJourneyActive(_ id: UUID, active: Bool) {
        if active {
            journeys = journeys.map { journey in
                var copy = journey
                copy.isActive = journey.id == id
                return copy
            }
        } else if let index = journeys.firstIndex(where: { $0.id == id }) {
            journeys[index].isActive = false
        }
        persistAndReloadWidgets()
    }

    /// Persists the current order (e.g. after manual drag reordering).
    func persistOrder() {
        store.save(journeys)
    }

    private func persistAndReloadWidgets() {
        store.save(journeys)
        // WidgetCenter is main-actor-bound; route the reload there so the
        // request is never silently dropped when called from another context.
        Task { @MainActor in
            WidgetCenter.shared.reloadAllTimelines()
        }
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
