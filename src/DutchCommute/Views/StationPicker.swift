import SwiftUI

/// A From/To row in the route diagram style (dot + connecting line, like
/// the journey cards): tapping the station name opens the picker sheet.
struct RouteStationRow: View {
    let label: LocalizedStringKey
    @Binding var station: Station?
    /// Whether a connecting line is drawn below the dot.
    var showsLine: Bool
    @State private var showPicker = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Palette.primary)
                    .frame(width: 9, height: 9)
                    .padding(.top, 3)
                if showsLine {
                    Rectangle()
                        .fill(Palette.primary.opacity(0.35))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.top, -4)
                        .padding(.bottom, -18)
                }
            }
            Button {
                showPicker = true
            } label: {
                HStack {
                    Text(station?.name ?? String(localized: "Select station"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(station == nil ? Palette.textTertiary : Palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showPicker) {
            StationPickerSheet(title: label, station: $station)
        }
    }
}

/// Full-height bottom sheet: search input on top, the shared search history
/// below (or autocomplete results while typing). Picking a station sets it
/// and stores it in the shared history.
struct StationPickerSheet: View {
    let title: LocalizedStringKey
    @Binding var station: Station?
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var suggestions: [StationChoice] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var hasSearched = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    historyList
                } else {
                    resultsList
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task {
            await state.loadStationChoices()
            searchFocused = true
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.textTertiary)
            TextField("Search stations", text: $query)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .onChange(of: query) { _, newValue in
                    scheduleSearch(query: newValue)
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// Previously picked stations, shared between the From and To pickers.
    private var historyList: some View {
        List {
            if state.stationHistory.isEmpty {
                Text("Start typing to search stations.")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
            } else {
                Section("History") {
                    ForEach(state.stationHistory) { station in
                        Button {
                            select(station)
                        } label: {
                            StationRow(
                                name: station.name,
                                mode: state.stationChoices.first { $0.id == station.code }?.mode
                            )
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
    }

    private var resultsList: some View {
        List {
            Section("Results") {
                ForEach(suggestions) { choice in
                    Button {
                        select(choice)
                    } label: {
                        StationRow(name: choice.name, mode: choice.mode)
                    }
                }
                if suggestions.isEmpty && hasSearched {
                    Text("No stations found.")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
    }

    /// Debounced autocomplete: only search once the user hasn't typed for
    /// 500 ms, so the station list is not fetched/filtered per keystroke.
    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        let snapshot = query
        guard snapshot.trimmingCharacters(in: .whitespaces).count >= 2 else {
            suggestions = []
            hasSearched = false
            return
        }
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await state.loadStationChoices()
            suggestions = Self.filter(state.stationChoices, query: snapshot)
            hasSearched = true
        }
    }

    private func select(_ choice: StationChoice) {
        select(Station(code: choice.id, name: choice.name))
    }

    private func select(_ station: Station) {
        self.station = station
        state.addToStationHistory(station)
        dismiss()
    }

    /// Ranks stations: prefix matches first, then contains; capped at 8.
    /// Returns no suggestions until the query has 2+ non-whitespace characters.
    static func filter(_ choices: [StationChoice], query: String) -> [StationChoice] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        let matches = choices.filter {
            $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q)
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

/// One autocomplete row: mode icon + station name, with the mode label
/// (icon + train/bus/metro/tram) below.
/// One picker row: big mode icon + station name, with the mode type below.
/// History rows fall back to a clock icon (and no type line) when the
/// stop's mode is no longer known.
private struct StationRow: View {
    let name: String
    let mode: TransportMode?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: mode?.icon ?? "clock")
                .font(.system(size: 30))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                if let mode {
                    Text(mode.label)
                        .font(.caption2)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }
}
