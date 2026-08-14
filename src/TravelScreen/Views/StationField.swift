import SwiftUI

/// Autocompleting station picker backed by the NS stations API.
struct StationField: View {
    let label: String
    @Binding var station: Station?

    @Environment(AppState.self) private var state
    @FocusState private var focused: Bool
    @State private var query = ""
    @State private var suggestions: [Station] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField(label, text: $query)
                .focused($focused)
                .autocorrectionDisabled()
                .onChange(of: query) { _, newValue in
                    if let station, newValue != station.name {
                        self.station = nil
                    }
                    scheduleSearch()
                }
                .onChange(of: focused) { _, isFocused in
                    if isFocused { scheduleSearch() }
                }

            if focused {
                if suggestions.isEmpty, state.stationsErrorMessage != nil {
                    Text(state.stationsErrorMessage!)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                ForEach(suggestions) { suggestion in
                    Button {
                        select(suggestion)
                    } label: {
                        HStack {
                            Text(suggestion.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(suggestion.code)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let snapshot = query
        searchTask = Task { @MainActor in
            await state.loadStations()
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            suggestions = Self.filter(state.stations, query: snapshot)
        }
    }

    private func select(_ station: Station) {
        self.station = station
        query = station.name
        suggestions = []
        focused = false
    }

    /// Ranks stations: prefix matches first, then contains; capped at 8.
    static func filter(_ stations: [Station], query: String) -> [Station] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(stations.prefix(8)) }
        let matches = stations.filter {
            $0.name.lowercased().contains(q) || $0.code.lowercased().contains(q)
        }
        let ranked = matches.sorted { a, b in
            let aPrefix = a.name.lowercased().hasPrefix(q) ? 0 : 1
            let bPrefix = b.name.lowercased().hasPrefix(q) ? 0 : 1
            if aPrefix != bPrefix { return aPrefix < bPrefix }
            return a.name < b.name
        }
        return Array(ranked.prefix(8))
    }
}
