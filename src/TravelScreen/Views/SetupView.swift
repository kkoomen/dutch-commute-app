import SwiftUI

/// Configures the journey: route (with autocomplete), times, and days.
struct SetupView: View {
    @Environment(AppState.self) private var state

    /// The existing journey when editing; nil on first setup.
    let prefill: JourneyConfig?

    @State private var from: Station?
    @State private var to: Station?
    @State private var departDate: Date = SetupView.referenceDate.addingTimeInterval(8 * 3600)
    @State private var returnDate: Date = SetupView.referenceDate.addingTimeInterval(18 * 3600)
    @State private var days: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    init(prefill: JourneyConfig? = nil) {
        self.prefill = prefill
        if let prefill {
            _from = State(initialValue: prefill.from)
            _to = State(initialValue: prefill.to)
            _departDate = State(initialValue: Self.referenceDate.addingTimeInterval(TimeInterval(prefill.departMinutes * 60)))
            _returnDate = State(initialValue: Self.referenceDate.addingTimeInterval(TimeInterval(prefill.returnMinutes * 60)))
            _days = State(initialValue: prefill.days)
        }
    }

    /// Fixed reference day for the time pickers (2000-01-01, Amsterdam).
    private static let referenceDate = JourneySchedule.calendar.startOfDay(
        for: Date(timeIntervalSince1970: 946_684_800) // 2000-01-01 00:00 UTC
    )

    private var routeSet: Bool { from != nil && to != nil && from != to }

    var body: some View {
        NavigationStack {
            Form {
                if APIKey.ns.isEmpty {
                    Section {
                        Label(
                            "NS_API_KEY not configured — add it to src/.env and rebuild.",
                            systemImage: "key.slash"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }

                Section("Route") {
                    StationField(label: "From", station: $from)
                    StationField(label: "To", station: $to)
                    Button("Swap") {
                        let oldFrom = from
                        from = to
                        to = oldFrom
                    }
                    .disabled(!routeSet)
                }

                Section {
                    DatePicker(
                        "Depart",
                        selection: $departDate,
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(!routeSet)

                    DatePicker(
                        "Return",
                        selection: $returnDate,
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(!routeSet)

                    if !routeSet {
                        Text("Select a from and to station first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Times")
                } footer: {
                    Text("The journey is shown while the current time is at or before the return time; after that, the next configured day is shown.")
                }

                Section("Days") {
                    HStack(spacing: 8) {
                        ForEach(Weekday.allCases) { day in
                            DayToggle(day: day, isOn: days.contains(day)) { toggle(day) }
                        }
                    }
                }

                Section {
                    Button(prefill == nil ? "Show my journey" : "Save changes") {
                        save()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(!routeSet || days.isEmpty)
                }
            }
            .navigationTitle("TravelScreen")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if prefill != nil {
                        Button("Cancel") {
                            state.cancelEditing()
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ day: Weekday) {
        if days.contains(day) {
            days.remove(day)
        } else {
            days.insert(day)
        }
    }

    private func save() {
        guard let from, let to, !days.isEmpty else { return }
        let calendar = JourneySchedule.calendar
        let config = JourneyConfig(
            from: from,
            to: to,
            departMinutes: minutes(of: departDate, calendar: calendar),
            returnMinutes: minutes(of: returnDate, calendar: calendar),
            days: days
        )
        state.save(config)
    }

    private func minutes(of date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}

/// A single Monday–Sunday select box.
private struct DayToggle: View {
    let day: Weekday
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(day.shortName)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isOn ? Color.accentColor : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(isOn ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.shortName)
        .accessibilityValue(isOn ? "Selected" : "Not selected")
    }
}

#Preview {
    SetupView()
        .environment(AppState())
}
