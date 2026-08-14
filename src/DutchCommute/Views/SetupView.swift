import SwiftUI

/// Configures a journey: route (with autocomplete), times, and days.
/// Pushed with `prefill` when editing an existing journey.
struct SetupView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    /// The existing journey when editing; nil when creating a new one.
    let prefill: JourneyConfig?

    @State private var from: Station?
    @State private var to: Station?
    @State private var via: Station?
    @State private var transportModes: Set<TransportMode> = Set(TransportMode.allCases)
    @State private var showTravelOptions = false
    /// nil until the user picks a real departure time (rows show "Tap to set").
    @State private var departMinutes: Int?
    @State private var returnMinutes: Int?
    @State private var days: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    @State private var timePickerTarget: TimePickerTarget?

    init(prefill: JourneyConfig? = nil) {
        self.prefill = prefill
        if let prefill {
            _from = State(initialValue: prefill.from)
            _to = State(initialValue: prefill.to)
            _via = State(initialValue: prefill.via)
            _transportModes = State(initialValue: prefill.transportModes)
            _departMinutes = State(initialValue: prefill.departMinutes)
            _returnMinutes = State(initialValue: prefill.returnMinutes)
            _days = State(initialValue: prefill.days)
        }
    }

    private var routeSet: Bool { from != nil && to != nil && from != to }

    var body: some View {
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
                if let via {
                    Button {
                        showTravelOptions = true
                    } label: {
                        HStack {
                            Text("Via")
                            Spacer()
                            Text(via.name)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                StationField(label: "To", station: $to)
                Button {
                    showTravelOptions = true
                } label: {
                    HStack {
                        Text("Travel options")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Section {
                if !routeSet {
                    Text("Select a from and to station first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        timePickerTarget = .depart
                    } label: {
                        HStack {
                            Text("Outbound")
                            Spacer()
                            Text(departMinutes.map { Self.timeString($0) } ?? String(localized: "Tap to set"))
                                .foregroundStyle(departMinutes == nil ? .tertiary : .secondary)
                        }
                    }
                    Button {
                        timePickerTarget = .return
                    } label: {
                        HStack {
                            Text("Return")
                            Spacer()
                            Text(returnMinutes.map { Self.timeString($0) } ?? String(localized: "Tap to set"))
                                .foregroundStyle(returnMinutes == nil ? .tertiary : .secondary)
                        }
                    }
                }
            } header: {
                Text("Times")
            }

            Section("Days") {
                HStack(spacing: 8) {
                    ForEach(Weekday.allCases) { day in
                        DayToggle(day: day, isOn: days.contains(day)) { toggle(day) }
                    }
                }
            }

            Section {
                Button(prefill == nil ? String(localized: "Add journey") : String(localized: "Save changes")) {
                    save()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!routeSet || days.isEmpty || departMinutes == nil || returnMinutes == nil)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
            }
        }
        .navigationTitle(prefill == nil ? String(localized: "New journey") : String(localized: "Edit journey"))
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .sheet(item: $timePickerTarget) { target in
            if let from, let to {
                TimePickerSheet(
                    title: target == .depart ? "Outbound" : "Return",
                    defaultHour: target == .depart ? 8 : 18,
                    from: target == .depart ? from : to,
                    to: target == .depart ? to : from,
                    via: effectiveVia,
                    transportModes: transportModes,
                    client: state.client,
                    selection: target == .depart ? $departMinutes : $returnMinutes
                )
            }
        }
        .sheet(isPresented: $showTravelOptions) {
            TravelOptionsSheet(transportModes: $transportModes, via: $via)
        }
    }

    /// The via station only counts when it differs from both endpoints.
    private var effectiveVia: Station? {
        guard let via, via != from, via != to else { return nil }
        return via
    }

    fileprivate static func timeString(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    fileprivate static func minutes(of date: Date) -> Int {
        let calendar = JourneySchedule.calendar
        return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    /// Today (Amsterdam) at the given minute-of-day — the date used for the
    /// single trips request.
    fileprivate static func date(todayAt minutes: Int) -> Date {
        let calendar = JourneySchedule.calendar
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: minutes, to: start)!
    }

    private func toggle(_ day: Weekday) {
        if days.contains(day) {
            days.remove(day)
        } else {
            days.insert(day)
        }
    }

    private func save() {
        guard let from, let to, let departMinutes, let returnMinutes, !days.isEmpty else { return }
        if var existing = prefill {
            existing.from = from
            existing.to = to
            existing.via = effectiveVia
            existing.transportModes = transportModes
            existing.departMinutes = departMinutes
            existing.returnMinutes = returnMinutes
            existing.days = days
            state.updateJourney(existing)
        } else {
            state.addJourney(JourneyConfig(
                id: UUID(),
                createdAt: Date(),
                from: from,
                via: effectiveVia,
                to: to,
                departMinutes: departMinutes,
                returnMinutes: returnMinutes,
                days: days,
                transportModes: transportModes
            ))
        }
        dismiss()
    }
}

/// Which time is being picked in the modal.
private enum TimePickerTarget: Identifiable {
    case depart
    case `return`

    var id: Self { self }
}

/// Bottom sheet: a wheel sets the preferred time; every change triggers one
/// `/v3/trips` request (today at that time, cached 2 minutes) and the sheet
/// shows whatever comes back (~5 times). Picking one sets the journey time;
/// the preferred time itself is never stored.
private struct TimePickerSheet: View {
    let title: LocalizedStringKey
    /// Hour the wheel starts at when nothing is picked yet (08:00 outbound,
    /// 18:00 return).
    let defaultHour: Int
    let from: Station
    let to: Station
    let via: Station?
    let transportModes: Set<TransportMode>
    let client: NSAPIClient
    @Binding var selection: Int?
    @Environment(\.dismiss) private var dismiss

    @State private var preferredDate: Date
    @State private var results: [Int] = []
    @State private var hasSearched = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var manualDate: Date

    init(title: LocalizedStringKey, defaultHour: Int, from: Station, to: Station, via: Station?, transportModes: Set<TransportMode>, client: NSAPIClient, selection: Binding<Int?>) {
        self.title = title
        self.defaultHour = defaultHour
        self.from = from
        self.to = to
        self.via = via
        self.transportModes = transportModes
        self.client = client
        _selection = selection
        // Start the wheel at the current value when editing, else the default
        // hour for this leg (08:00 outbound, 18:00 return).
        _preferredDate = State(
            initialValue: selection.wrappedValue.map { SetupView.date(todayAt: $0) }
                ?? SetupView.date(todayAt: defaultHour * 60)
        )
        _manualDate = State(initialValue: SetupView.date(todayAt: defaultHour * 60))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Preferred time") {
                    DatePicker(
                        "Preferred time",
                        selection: $preferredDate,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .onChange(of: preferredDate) { _, newValue in
                        scheduleSearch(at: newValue)
                    }
                }

                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Searching departure times…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Retry") { scheduleSearch(at: preferredDate) }
                    }
                    manualFallback
                } else if !results.isEmpty {
                    Section("Departures") {
                        ForEach(results, id: \.self) { minute in
                            Button {
                                selection = minute
                                dismiss()
                            } label: {
                                HStack {
                                    Text(SetupView.timeString(minute))
                                    Spacer()
                                    if minute == selection {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }
                } else if hasSearched {
                    Section {
                        Text("No trains found at \(SetupView.timeString(SetupView.minutes(of: preferredDate))).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    manualFallback
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task { scheduleSearch(at: preferredDate) }
    }

    /// Manual picker so a time can still be set without the API.
    private var manualFallback: some View {
        Section {
            HStack {
                DatePicker("Manual time", selection: $manualDate, displayedComponents: .hourAndMinute)
                Button("Set") {
                    selection = SetupView.minutes(of: manualDate)
                    dismiss()
                }
            }
        }
    }

    /// Debounced search: wheel changes fire often, so wait until the value
    /// settles, then run one cached trips request for today at that time.
    private func scheduleSearch(at date: Date) {
        searchTask?.cancel()
        let snapshot = date
        isLoading = true
        errorMessage = nil
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            hasSearched = true
            do {
                let minutes = try await client.departureMinutes(from: from, to: to, via: via, transportModes: transportModes, at: snapshot)
                guard !Task.isCancelled else { return }
                results = minutes
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

/// Full-height modal with the transport mode multi-select (all selected by
/// default, at least one required) and the optional via station. The blue
/// checkmark closes it; changes apply to the form immediately.
private struct TravelOptionsSheet: View {
    @Binding var transportModes: Set<TransportMode>
    @Binding var via: Station?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Transport") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(TransportMode.allCases) { mode in
                            TransportModeTile(mode: mode, isSelected: transportModes.contains(mode)) {
                                toggle(mode)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    Text("At least one mode is required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Via station (optional)") {
                    StationField(label: "Via", station: $via)
                }
            }
            .navigationTitle("Travel options")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                    }
                    .accessibilityLabel("Done")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    /// Toggles a mode, refusing to remove the last selected one.
    private func toggle(_ mode: TransportMode) {
        if transportModes.contains(mode) {
            guard transportModes.count > 1 else { return }
            transportModes.remove(mode)
        } else {
            transportModes.insert(mode)
        }
    }
}

/// One selectable transport mode tile: icon with the name below it.
private struct TransportModeTile: View {
    let mode: TransportMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.title2)
                    .frame(height: 26)
                Text(mode.label)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(isSelected ? Palette.primary : Palette.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Palette.primary.opacity(0.15) : Palette.surfaceSecondary)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Palette.primary : .clear, lineWidth: 1.5)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Palette.primary)
                        .background(Circle().fill(Palette.surface))
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.label)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
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
                .background(isOn ? Palette.primary : Palette.surfaceSecondary, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(isOn ? Palette.onAccent : Palette.textPrimary)
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
