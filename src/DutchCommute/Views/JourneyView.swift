import SwiftUI

/// Shows the active journey: date, both legs, and live status.
struct JourneyView: View {
    @Environment(AppState.self) private var state
    let config: JourneyConfig

    @State private var journeyDate: Date?
    @State private var legs: [LegKind: TrainLeg] = [:]
    @State private var errorMessage: String?
    @State private var showLockScreenHelp = false
    @State private var showNearDepartureHelp = false

    /// Live Activity eligibility: both stops must be train stations.
    private var isLiveActivityEligible: Bool {
        LiveActivityManager.isEligible(config, choices: state.stationChoices)
    }

    /// The journey's current live-activity setting (from state, not the
    /// immutable config passed in).
    private var showsLiveActivity: Bool {
        state.journeys.first(where: { $0.id == config.id })?.showsLiveActivity ?? false
    }

    private let autoRefresh = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
                if journeyDate != nil {
                    Section("Outbound") {
                        LegCard(
                            fromName: config.from.name,
                            toName: config.to.name,
                            defaultTime: NSDateParser.timeString(minutes: config.departMinutes),
                            leg: legs[.outbound]
                        )
                    }

                    Section("Return") {
                        LegCard(
                            fromName: config.to.name,
                            toName: config.from.name,
                            defaultTime: NSDateParser.timeString(minutes: config.returnMinutes),
                            leg: legs[.returnLeg]
                        )
                    }
                } else {
                    Text("No travel days configured.")
                        .foregroundStyle(.secondary)
                }

                Section("Days") {
                    HStack(spacing: 8) {
                        ForEach(Weekday.allCases) { day in
                            DayTile(day: day, isOn: config.days.contains(day))
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let errorMessage {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("Showing scheduled times only when available.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Toggle("Show on lockscreen", isOn: Binding(
                        get: { state.journeys.first(where: { $0.id == config.id })?.isActive ?? false },
                        set: { state.setJourneyActive(config.id, active: $0) }
                    ))
                    Button {
                        showLockScreenHelp = true
                    } label: {
                        Text("Read here how to add this widget to your lockscreen.")
                            .font(.caption)
                            .foregroundStyle(Palette.primary)
                    }
                }

                Section {
                    Toggle("Show live activity", isOn: Binding(
                        get: { state.journeys.first(where: { $0.id == config.id })?.showsLiveActivity ?? false },
                        set: { state.setShowsLiveActivity(config.id, shows: $0) }
                    ))
                    .disabled(!isLiveActivityEligible)
                    Text("Only available for journeys between two train stations.")
                        .font(.caption2)
                        .foregroundStyle(Palette.textSecondary)
                    Toggle(isOn: Binding(
                        get: { state.journeys.first(where: { $0.id == config.id })?.showsNearDeparture ?? false },
                        set: { state.setShowsNearDeparture(config.id, shows: $0) }
                    )) {
                        HStack(spacing: 6) {
                            Text("Show near departure")
                            Button {
                                showNearDepartureHelp = true
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                    .disabled(!showsLiveActivity)
                }
                .alert("Show near departure", isPresented: $showNearDepartureHelp) {
                    Button("Done", role: .cancel) {}
                } message: {
                    Text("Turn this on to start the Live Activity 1 hour before departure.")
                }
            }
            .sheet(isPresented: $showLockScreenHelp) {
                LockScreenHelpView()
            }
            .navigationTitle("My journey")
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        state.path.append(.setup(config.id))
                    }
                }
            }
            .refreshable { await reload() }
            .task {
                await state.loadStationChoices()
                await reload()
            }
            .onReceive(autoRefresh) { _ in
                Task { await reload() }
            }
    }

    private func reload() async {
        guard let date = JourneySchedule.nextJourneyDate(now: Date(), config: config) else {
            journeyDate = nil
            legs = [:]
            return
        }
        journeyDate = date

        let times = JourneySchedule.legTimes(on: date, config: config)
        do {
            async let outboundTrip = state.client.fetchTrip(from: config.from, to: config.to, at: times.outbound)
            async let returnTrip = state.client.fetchTrip(from: config.to, to: config.from, at: times.return)
            let (outbound, returnLeg) = try await (outboundTrip, returnTrip)
            legs[.outbound] = outbound.firstLeg.flatMap(TrainLeg.init)
            legs[.returnLeg] = returnLeg.firstLeg.flatMap(TrainLeg.init)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One train leg card: route diagram (stations with tracks), time, status.
/// Before the live leg arrives it shows the saved departure time with an
/// "On time" chip; the live time/status replace it in place.
private struct LegCard: View {
    let fromName: String
    let toName: String
    /// Locally saved departure time, shown until live data arrives.
    let defaultTime: String
    let leg: TrainLeg?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StationRouteView(stations: stationNames)
            Spacer()
            if let leg {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(NSDateParser.timeString(leg.displayedDeparture))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(leg.status == .cancelled ? Palette.textTertiary : Palette.textPrimary)
                        .strikethrough(leg.status == .cancelled)
                    StatusChip(status: leg.status)
                }
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(defaultTime)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                    StatusChip(status: .onTime)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var stationNames: [String] {
        [fromName, toName]
    }
}

/// Short instructions for adding the widget to the Lock Screen.
private struct LockScreenHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                step("1", String(localized: "Press and hold the Lock Screen, then tap Customize."))
                step("2", String(localized: "Tap Add Widget and search for \"Dutch Commute\"."))
                step("3", String(localized: "Add the \"My journey\" widget — it shows your next train and its live status."))
                Spacer()
            }
            .padding()
            .navigationTitle("Add widget")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .frame(width: 22)
                .foregroundStyle(Palette.textPrimary)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Palette.textPrimary)
        }
    }
}

private struct StatusChip: View {
    let status: TrainStatus

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .onTime: Palette.statusOnTime
        case .delayed: .orange
        case .cancelled: .red
        case .unknown: .gray
        }
    }
}
