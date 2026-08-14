import SwiftUI

/// Autocompleting station picker backed by the NS stations API.
struct StationField: View {
    let label: LocalizedStringKey
    @Binding var station: Station?

    @Environment(AppState.self) private var state
    @FocusState private var focused: Bool
    @State private var query: String
    @State private var suggestions: [Station] = []
    @State private var searchTask: Task<Void, Never>?

    init(label: LocalizedStringKey, station: Binding<Station?>) {
        self.label = label
        _station = station
        // Seed the text field from the bound station (e.g. when editing a
        // saved journey, the field must show the existing station name).
        _query = State(initialValue: station.wrappedValue?.name ?? "")
    }

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
                .onChange(of: station) { _, newValue in
                    if let newValue {
                        query = newValue.name
                    }
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
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(suggestions) { suggestion in
                            Button {
                                select(suggestion)
                            } label: {
                                HStack {
                                    Text(suggestion.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 38)
                                .contentShape(Rectangle())
                            }
                        }
                    }
                }
                // Show at most 3 rows (3 × 38 pt); more scroll.
                .frame(maxHeight: 114)
            }
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let snapshot = query
        guard snapshot.trimmingCharacters(in: .whitespaces).count >= 2 else {
            // Only autocomplete once the user has typed 2+ non-whitespace
            // characters; clear any stale suggestions right away.
            suggestions = []
            return
        }
        searchTask = Task { @MainActor in
            // Debounce: only search once the user hasn't typed for 500 ms,
            // so the station list is not fetched/filtered on every keystroke.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await state.loadStations()
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
    /// Returns no suggestions until the query has 2+ non-whitespace characters.
    static func filter(_ stations: [Station], query: String) -> [Station] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
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
