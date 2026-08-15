import SwiftUI

/// Shows the journey as configured: both legs with the saved times, the
/// days, and the lock screen / live activity toggles. No live data.
struct JourneyView: View {
    @Environment(AppState.self) private var state
    let config: JourneyConfig

    @State private var showLockScreenHelp = false
    @State private var showNearDepartureHelp = false
    @State private var showLiveActivityHelp = false

    /// Live Activity eligibility: both stops must be train stations.
    private var isLiveActivityEligible: Bool {
        LiveActivityManager.isEligible(config, choices: state.stationChoices)
    }

    /// The journey's current live-activity setting (from state, not the
    /// immutable config passed in).
    private var showsLiveActivity: Bool {
        state.journeys.first(where: { $0.id == config.id })?.showsLiveActivity ?? false
    }

    /// The journey date to show; nil when no days are configured.
    private var journeyDate: Date? {
        JourneySchedule.nextJourneyDate(now: Date(), config: config)
    }

    var body: some View {
        List {
                if journeyDate != nil {
                    Section("Outbound") {
                        LegCard(
                            fromName: config.from.name,
                            toName: config.to.name,
                            departureTime: NSDateParser.timeString(minutes: config.departMinutes)
                        )
                    }

                    Section("Return") {
                        LegCard(
                            fromName: config.to.name,
                            toName: config.from.name,
                            departureTime: NSDateParser.timeString(minutes: config.returnMinutes)
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
                    Toggle(isOn: Binding(
                        get: { state.journeys.first(where: { $0.id == config.id })?.showsLiveActivity ?? false },
                        set: { state.setShowsLiveActivity(config.id, shows: $0) }
                    )) {
                        HStack(spacing: 6) {
                            Text("Show live activity")
                            Button {
                                showLiveActivityHelp = true
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
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
                .alert("Show live activity", isPresented: $showLiveActivityHelp) {
                    Button("Done", role: .cancel) {}
                } message: {
                    Text("Only available for journeys between two train stations.")
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
    }
}

/// One train leg card: route diagram (stations with tracks) and the saved
/// departure time.
private struct LegCard: View {
    let fromName: String
    let toName: String
    /// Locally saved departure time.
    let departureTime: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StationRouteView(stations: stationNames)
            Spacer()
            Text(departureTime)
                .font(.title3.monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
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
