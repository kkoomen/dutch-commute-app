import SwiftUI

/// Home screen: all journeys, newest first, reorderable by dragging the
/// grip on the left of each card.
struct JourneyListView: View {
    @Environment(AppState.self) private var state
    /// Set when the user swipes to delete; shown in a bottom confirmation
    /// sheet.
    @State private var journeyPendingDeletion: JourneyConfig?
    /// Set when the user confirms deletion in the sheet; the deletion runs
    /// in `onDismiss`, after the sheet has fully gone — removing the row
    /// while the sheet is still dismissing (and its swipe action is
    /// active) crashes SwiftUI's List bookkeeping.
    @State private var journeyToDeleteAfterDismissal: JourneyConfig?

    /// Opens the confirmation sheet for `journey`.
    ///
    /// The swipe action is still collapsing when its button action runs;
    /// presenting the sheet right then makes SwiftUI's List drop the row
    /// from the visible list even though the journey is not deleted (the
    /// row only comes back after an app restart). Deferring the
    /// presentation until the collapse animation has finished keeps the
    /// row on screen until the user actually confirms deletion.
    private func requestDeletion(of journey: JourneyConfig) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            journeyPendingDeletion = journey
        }
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
                                        .labelStyle(.titleAndIcon)
                                }
                                .tint(Palette.primary)
                            }
                            // Custom trailing action instead of `.onDelete`:
                            // the system delete button removes the row the
                            // moment it is tapped, before any confirmation.
                            // This one only opens the confirmation sheet;
                            // the journey is deleted there, on confirm.
                            // `allowsFullSwipe: false` stops the swipe at
                            // the revealed button — a full swipe must not
                            // trigger anything by itself.
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // Do not mark the swipe action destructive:
                                // SwiftUI may remove the List row immediately
                                // for destructive swipe buttons. The actual
                                // destructive action lives in the confirmation
                                // sheet.
                                Button {
                                    requestDeletion(of: journey)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                        .labelStyle(.titleAndIcon)
                                }
                                .tint(.red)
                            }
                    }
                    .onMove { source, destination in
                        var updated = state.journeys
                        updated.move(fromOffsets: source, toOffset: destination)
                        state.journeys = updated
                    }
                    } header: {
                        Text("Swipe right on a journey to make it active, swipe left to delete it, or tap a journey to view or edit it. The active journey will be visible on the lock screen widget.")
                            .font(.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.bottom, 2)
                    }
                }
            }
        }
        .sheet(item: $journeyPendingDeletion, onDismiss: {
            if let pending = journeyToDeleteAfterDismissal {
                journeyToDeleteAfterDismissal = nil
                state.deleteJourney(pending.id)
            }
        }) { journey in
            DeleteConfirmationSheet {
                journeyToDeleteAfterDismissal = journey
            }
        }
        .navigationTitle("My journeys")
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    state.path.append(.setup(nil))
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add journey")
            }
            // Declared after the "+" button so it sits to its left.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    state.path.append(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
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
                if journey.showsLiveActivity {
                    Text("Live")
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
