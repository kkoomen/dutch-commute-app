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
        NavigationStack {
            List {
                if let date = journeyDate {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dateTitle(for: date))
                                .font(.title3.bold())
                            Text("\(config.from.name) → \(config.to.name)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("Departure") {
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        state.startEditing()
                    }
                }
            }
            .refreshable { await reload() }
            .task { await reload() }
            .onReceive(autoRefresh) { _ in
                Task { await reload() }
            }
        }
    }

    private func dateTitle(for date: Date) -> String {
        let calendar = JourneySchedule.calendar
        let prefix: String
        if calendar.isDateInToday(date) {
            prefix = "Today"
        } else if calendar.isDateInTomorrow(date) {
            prefix = "Tomorrow"
        } else {
            prefix = ""
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE d MMM"
        let short = formatter.string(from: date)
        return prefix.isEmpty ? short : "\(prefix) · \(short)"
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

/// One train leg card: train, direction, time, and status.
private struct LegCard: View {
    let title: String
    let leg: TrainLeg?
    let isLoading: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let leg {
                    Text("🚆 \(leg.name)")
                        .font(.headline)
                    if !leg.direction.isEmpty {
                        Text("→ \(leg.direction)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if let leg {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(NSDateParser.timeString(leg.displayedDeparture))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(leg.status == .cancelled ? .secondary : .primary)
                        .strikethrough(leg.status == .cancelled)
                    StatusChip(status: leg.status)
                }
            } else if isLoading {
                ProgressView()
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
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
                step("1", "Press and hold the Lock Screen, then tap Customize.")
                step("2", "Tap Add Widget and search for \"Travel Screen\".")
                step("3", "Add the \"My journey\" widget — it shows your next train and its live status.")
                Spacer()
            }
            .padding()
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
                .background(Color.accentColor.opacity(0.15), in: Circle())
                .foregroundStyle(.primary)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
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
        case .onTime: .green
        case .delayed: .orange
        case .cancelled: .red
        case .unknown: .gray
        }
    }
}
