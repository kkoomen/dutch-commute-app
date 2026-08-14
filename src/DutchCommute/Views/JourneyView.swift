import SwiftUI

/// Shows the active journey: date, both legs, and live status.
struct JourneyView: View {
    @Environment(AppState.self) private var state
    let config: JourneyConfig

    @State private var journeyDate: Date?
    @State private var legs: [LegKind: TrainLeg] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showLockScreenHelp = false

    private let autoRefresh = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
                if journeyDate != nil {
                    Section("Outbound") {
                        LegCard(
                            title: "\(config.from.name) → \(config.to.name)",
                            leg: legs[.outbound],
                            isLoading: isLoading
                        )
                    }

                    Section("Return") {
                        LegCard(
                            title: "\(config.to.name) → \(config.from.name)",
                            leg: legs[.returnLeg],
                            isLoading: isLoading
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
                    Button {
                        showLockScreenHelp = true
                    } label: {
                        Label("Add to lock screen", systemImage: "lock.iphone")
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
        isLoading = true
        defer { isLoading = false }

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

/// One train leg card: train, direction, time, and status.
private struct LegCard: View {
    let title: String
    let leg: TrainLeg?
    let isLoading: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Palette.textPrimary)
                if let leg {
                    Text("🚆 \(leg.name)")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textPrimary)
                    if !leg.direction.isEmpty {
                        Text("→ \(leg.direction)")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            Spacer()
            if let leg {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(NSDateParser.timeString(leg.displayedDeparture))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(leg.status == .cancelled ? Palette.textTertiary : Palette.textPrimary)
                        .strikethrough(leg.status == .cancelled)
                    StatusChip(status: leg.status)
                }
            } else if isLoading {
                ProgressView()
            } else {
                Text("—")
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.vertical, 4)
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
            .background(Palette.surface)
            .navigationTitle("Add to lock screen")
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
                .frame(width: 22, height: 22)
                .background(Palette.primary.opacity(0.15), in: Circle())
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
