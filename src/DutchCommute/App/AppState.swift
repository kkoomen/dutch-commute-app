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
    /// Selectable stops: NS train stations plus GTFS bus/metro/tram stops
    /// (when static GTFS data is bundled).
    var stationChoices: [StationChoice] = []
    private(set) var stationChoicesLoaded = false
    /// Bundled GTFS stop departures (stop id → minutes of day), loaded
    /// lazily when the time picker needs them.
    private(set) var gtfsDepartureMinutes: [String: [Int]] = [:]
    private var gtfsDeparturesLoaded = false
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
        applyLiveActivities()
    }

    func updateJourney(_ journey: JourneyConfig) {
        guard let index = journeys.firstIndex(where: { $0.id == journey.id }) else { return }
        journeys[index] = journey
        persistAndReloadWidgets()
        applyLiveActivities()
    }

    func deleteJourneys(at offsets: IndexSet) {
        journeys.remove(atOffsets: offsets)
        persistAndReloadWidgets()
        applyLiveActivities()
    }

    /// Deletes one journey by id (after user confirmation in the UI).
    func deleteJourney(_ id: UUID) {
        journeys.removeAll { $0.id == id }
        persistAndReloadWidgets()
        applyLiveActivities()
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
        applyLiveActivities()
    }

    /// Toggles the Live Activity for a journey (persisted; the activity is
    /// started/ended accordingly).
    func setShowsLiveActivity(_ id: UUID, shows: Bool) {
        guard let index = journeys.firstIndex(where: { $0.id == id }) else { return }
        journeys[index].showsLiveActivity = shows
        if !shows {
            journeys[index].showsNearDeparture = false
        }
        persistAndReloadWidgets()
        applyLiveActivities()
    }

    /// Toggles near-departure-only Live Activity mode.
    func setShowsNearDeparture(_ id: UUID, shows: Bool) {
        guard let index = journeys.firstIndex(where: { $0.id == id }) else { return }
        journeys[index].showsNearDeparture = shows
        persistAndReloadWidgets()
        applyLiveActivities()
    }

    /// Reconciles running Live Activities with the current journeys.
    func applyLiveActivities() {
        Task { @MainActor in
            await loadStationChoices()
            await LiveActivityManager.apply(journeys: journeys, choices: stationChoices)
        }
    }

    /// Whether the time picker should use the NS API for a leg — based on
    /// the leg's **departure stop** only (the from stop for the outbound
    /// leg, the to stop for the return leg). Unknown stops fall back to
    /// the NS API (historical behavior).
    static func usesNSAPI(departureStop: Station, choices: [StationChoice]) -> Bool {
        let mode = choices.first { $0.id == departureStop.code }?.mode ?? .train
        return mode == .train
    }

    /// Departure minutes for the time picker: NS API when the leg departs
    /// from a train station; bundled GTFS stop departures otherwise
    /// (bus/metro/tram). The departure stop is `from` for the outbound
    /// leg and the journey's `to` for the return leg.
    /// GTFS departures are direction-agnostic — NL stops are per-direction.
    func departureMinutes(from: Station, to: Station, at preferred: Date) async throws -> [Int] {
        if Self.usesNSAPI(departureStop: from, choices: stationChoices) {
            return try await client.departureMinutes(from: from, to: to, at: preferred)
        }
        await ensureGTFSDeparturesLoaded()
        return GTFSStaticDataService.departureMinutes(from: from.code, data: gtfsDepartureMinutes, at: preferred)
    }

    /// Loads the bundled GTFS stop departures once (first GTFS time search).
    private func ensureGTFSDeparturesLoaded() async {
        guard !gtfsDeparturesLoaded else { return }
        if let url = Bundle.main.url(forResource: "gtfs", withExtension: nil) {
            gtfsDepartureMinutes = GTFSStaticDataService.loadDepartureMinutes(from: url.appendingPathComponent("departures.bin.gz"))
        }
        gtfsDeparturesLoaded = true
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

    /// Loads the selectable stops (NS train stations + bundled GTFS stops)
    /// once for the station picker.
    func loadStationChoices() async {
        guard !stationChoicesLoaded else { return }
        await loadStations()
        let nsChoices = stations.map { StationChoice(id: $0.code, name: $0.name, mode: .train) }
        var gtfsChoices: [StationChoice] = []
        // Static GTFS data is bundled under Resources/gtfs/ when present;
        // without it only NS train stations are offered.
        if let url = Bundle.main.url(forResource: "gtfs", withExtension: nil),
           let data = try? GTFSStaticDataService.load(from: url) {
            gtfsChoices = GTFSStaticDataService.stationChoices(from: data)
        }
        stationChoices = nsChoices + gtfsChoices
        stationChoicesLoaded = true
    }
}
