import SwiftUI
import UniformTypeIdentifiers

/// Home screen: all journeys, newest first, reorderable by dragging the
/// grip on the left of each card.
struct JourneyListView: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @State private var draggedJourneyID: UUID?

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
                    ForEach(state.journeys) { journey in
                        JourneyCard(journey: journey)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                state.path.append(.journey(journey.id))
                            }
                            .onDrag {
                                draggedJourneyID = journey.id
                                return NSItemProvider(object: journey.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: JourneyDropDelegate(
                                    destination: journey,
                                    journeys: $state.journeys,
                                    draggedID: $draggedJourneyID
                                )
                            )
                    }
                    .onDelete { offsets in
                        state.deleteJourneys(at: offsets)
                    }
                }
            }
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

            Text(Self.daysLabel(journey.days))
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 1)
        }
        .padding(.vertical, 2)
    }

    /// "[from, via?, to]" — the route shown as the dot diagram.
    private var stationNames: [String] {
        [journey.from.name] + (journey.via.map { [$0.name] } ?? []) + [journey.to.name]
    }

    /// Outbound time left of the from station, return time left of the to
    /// station (via gets none).
    private var leadingTimes: [String?] {
        let depart = Self.timeString(journey.departMinutes)
        let returnTime = Self.timeString(journey.returnMinutes)
        return [depart] + (journey.via.map { _ in [nil] } ?? []) + [returnTime]
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

/// Moves the dragged journey to this row's position while dragging over it.
private struct JourneyDropDelegate: DropDelegate {
    let destination: JourneyConfig
    @Binding var journeys: [JourneyConfig]
    @Binding var draggedID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != destination.id,
              let from = journeys.firstIndex(where: { $0.id == draggedID }),
              let to = journeys.firstIndex(where: { $0.id == destination.id })
        else { return }
        withAnimation {
            journeys.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }
}

#Preview {
    NavigationStack {
        JourneyListView()
            .environment(AppState())
    }
}
