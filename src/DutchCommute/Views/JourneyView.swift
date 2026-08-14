import SwiftUI

/// Shows the active journey: date, both legs, and live status.
struct JourneyView: View {
    @Environment(AppState.self) private var state
    let config: JourneyConfig

    @State private var journeyDate: Date?
    @State private var legs: [LegKind: TrainLeg] = [:]
    @State private var errorMessage: String?
    @State private var showLockScreenHelp = false

    private let autoRefresh = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
                if journeyDate != nil {
                    Section("Outbound") {
                        LegCard(
                            fromName: config.from.name,
                            viaName: config.via?.name,
                            toName: config.to.name,
                            defaultTime: NSDateParser.timeString(minutes: config.departMinutes),
                            leg: legs[.outbound]
                        )
                    }

                    Section("Return") {
                        LegCard(
                            fromName: config.to.name,
                            viaName: config.via?.name,
                            toName: config.from.name,
                            defaultTime: NSDateParser.timeString(minutes: config.returnMinutes),
                            leg: legs[.returnLeg]
                        )
                    }
                } else {
                    Text("No travel days configured.")
                        .foregroundStyle(.secondary)
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
            .task { await reload() }
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
            async let outboundTrip = state.client.fetchTrip(from: config.from, to: config.to, at: times.outbound, via: config.via, transportModes: config.transportModes)
            async let returnTrip = state.client.fetchTrip(from: config.to, to: config.from, at: times.return, via: config.via, transportModes: config.transportModes)
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
    let viaName: String?
    let toName: String
    /// Locally saved departure time, shown until live data arrives.
    let defaultTime: String
    let leg: TrainLeg?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StationRouteView(stations: stationNames, captions: trackCaptions)
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
        [fromName] + (viaName.map { [$0] } ?? []) + [toName]
    }

    /// "Spoor X" under each station; with a via station the trip's first
    /// leg ends there, so the arrival track belongs to the via stop and the
    /// final station's track is not available.
    private var trackCaptions: [String?] {
        guard let leg else { return [] }
        let fromTrack = leg.departureTrack.map { String(localized: "Track \($0)") }
        let arrivalTrack = leg.arrivalTrack.map { String(localized: "Track \($0)") }
        if viaName != nil {
            return [fromTrack, arrivalTrack, nil]
        }
        return [fromTrack, arrivalTrack]
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
        .background(Palette.teal)
        .preferredColorScheme(.light)
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
