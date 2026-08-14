import SwiftUI

/// Home screen: all journeys, newest first, reorderable by dragging the
/// grip on the left of each card.
struct JourneyListView: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    /// Set when the user swipes to delete; shown in a confirmation dialog.
    @State private var journeyPendingDeletion: JourneyConfig?

    /// What is shown right now (resolves `.system` against the environment).
    private var effectiveAppearance: Appearance {
        Appearance.effective(Appearance(rawValue: appearance) ?? .system, colorScheme: colorScheme)
    }

    var body: some View {
        @Bindable var state = state
        Group {
            if state.journeys.isEmpty {
                ContentUnavailableView {
                    Text("No journeys yet")
                } description: {
                    Text("Add your first journey to see train status on the go.")
                }
            } else {
                List {
                    Section {
                        ForEach(state.journeys) { journey in
                        JourneyCard(journey: journey)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                state.path.append(.journey(journey.id))
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    state.setJourneyActive(journey.id, active: true)
                                } label: {
                                    Label("Activate", systemImage: "lock.fill")
                                }
                                .tint(Palette.primary)
                            }
                    }
                    .onMove { source, destination in
                        var updated = state.journeys
                        updated.move(fromOffsets: source, toOffset: destination)
                        state.journeys = updated
                    }
                    .onDelete { offsets in
                        if let index = offsets.first, state.journeys.indices.contains(index) {
                            journeyPendingDeletion = state.journeys[index]
                        }
                    }
                    } header: {
                        Text("Swipe right on a journey to make it active, swipe left to delete it, or tap a journey for its live status. The active journey will be visible on the lock screen widget.")
                            .font(.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.bottom, 2)
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete journey?",
            isPresented: Binding(
                get: { journeyPendingDeletion != nil },
                set: { if !$0 { journeyPendingDeletion = nil } }
            ),
            presenting: journeyPendingDeletion
        ) { journey in
            Button("Delete", role: .destructive) {
                state.deleteJourney(journey.id)
                journeyPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                journeyPendingDeletion = nil
            }
        } message: { _ in
            Text("This journey will be permanently removed.")
        }
        .navigationTitle("My journeys")
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { mode in
                            Label(mode.label, systemImage: mode.icon)
                                .tag(mode.rawValue)
                        }
                    }
                } label: {
                    Image(systemName: effectiveAppearance == .dark ? "moon.fill" : "sun.max.fill")
                }
                .accessibilityLabel("Appearance")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    state.path.append(.setup(nil))
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add journey")
            }
        }
        .onChange(of: state.journeys) { _, _ in
            state.persistOrder()
        }
    }
}

/// One journey card: route, times, days, absolute creation time,
/// and the drag grip on the left.
private struct JourneyCard: View {
    let journey: JourneyConfig

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Drag to reorder")
                Spacer(minLength: 0)
            }

            StationRouteView(stations: stationNames, leading: leadingTimes)

            VStack(alignment: .trailing, spacing: 4) {
                Text(Self.daysLabel(journey.days))
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                if journey.isActive {
                    Text("Active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    /// "[from, to]" — the route shown as the dot diagram.
    private var stationNames: [String] {
        [journey.from.name, journey.to.name]
    }

    /// Outbound time left of the from station, return time left of the to
    /// station.
    private var leadingTimes: [String?] {
        [Self.timeString(journey.departMinutes), Self.timeString(journey.returnMinutes)]
    }

    private static func timeString(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// "Mon–Fri" for a contiguous run, otherwise "Mon, Wed, Fri".
    private static func daysLabel(_ days: Set<Weekday>) -> String {
        let ordered = Weekday.allCases.filter { days.contains($0) }
        guard !ordered.isEmpty else { return String(localized: "No days") }
        let isContiguous = ordered.count == ordered.last!.rawValue - ordered.first!.rawValue + 1
        if isContiguous {
            return "\(ordered.first!.shortName)–\(ordered.last!.shortName)"
        }
        return ordered.map(\.shortName).joined(separator: ", ")
    }
}

#Preview {
    NavigationStack {
        JourneyListView()
            .environment(AppState())
    }
}
