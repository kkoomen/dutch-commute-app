import SwiftUI
import WidgetKit

/// One widget snapshot: the next leg of the configured journey.
struct JourneyEntry: TimelineEntry {
    let date: Date
    let config: JourneyConfig?
    let journeyDate: Date?
    let leg: TrainLeg?
    let legKind: LegKind?
}

struct JourneyTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> JourneyEntry {
        JourneyEntry(date: Date(), config: nil, journeyDate: nil, leg: nil, legKind: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (JourneyEntry) -> Void) {
        Task {
            completion(await makeEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JourneyEntry>) -> Void) {
        Task {
            let entry = await makeEntry()
            var policy: TimelineReloadPolicy = .after(Date().addingTimeInterval(15 * 60))
            if let leg = entry.leg {
                // Refresh shortly after this train departs so the next one takes over.
                policy = .after(leg.plannedDeparture.addingTimeInterval(5 * 60))
            }
            completion(Timeline(entries: [entry], policy: policy))
        }
    }

    /// Reads the shared journeys and fetches the next upcoming leg of the
    /// first (top-most) journey.
    private func makeEntry() async -> JourneyEntry {
        let now = Date()
        guard let config = ConfigStore().load().first else {
            return JourneyEntry(date: now, config: nil, journeyDate: nil, leg: nil, legKind: nil)
        }
        guard let journeyDate = JourneySchedule.nextJourneyDate(now: now, config: config) else {
            return JourneyEntry(date: now, config: config, journeyDate: nil, leg: nil, legKind: nil)
        }
        let times = JourneySchedule.legTimes(on: journeyDate, config: config)
        let kind = JourneySchedule.upcomingLeg(now: now, outbound: times.outbound, returnLeg: times.return)
        let departureTime = kind == .outbound ? times.outbound : times.return
        let from = kind == .outbound ? config.from : config.to
        let to = kind == .outbound ? config.to : config.from

        let leg: TrainLeg?
        do {
            let trip = try await NSAPIClient(apiKey: APIKey.ns).fetchTrip(from: from, to: to, at: departureTime, via: config.via, transportModes: config.transportModes)
            leg = trip.firstLeg.flatMap(TrainLeg.init)
        } catch {
            leg = nil
        }
        return JourneyEntry(date: now, config: config, journeyDate: journeyDate, leg: leg, legKind: kind)
    }
}

struct JourneyWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: JourneyEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                rectangular
            case .accessoryCircular:
                circular
            case .accessoryInline:
                inline
            default:
                system
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    /// Line 1: train + destination; line 2: leg + time; line 3: status.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let leg = entry.leg {
                Text("🚆 \(destinationName)")
                    .font(.headline)
                HStack(spacing: 4) {
                    Text(legKindLabel)
                    Text(NSDateParser.timeString(leg.displayedDeparture))
                        .font(.body.monospacedDigit())
                }
                .font(.caption)
                StatusLine(status: leg.status)
            } else if entry.config == nil {
                Text("Set up your journey in the Dutch Commute app")
                    .font(.caption)
            } else {
                Text("No train right now")
                    .font(.caption)
            }
        }
    }

    /// Home screen families (systemSmall / systemMedium / systemLarge /
    /// systemExtraLarge): same three-line structure, roomier.
    private var system: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let leg = entry.leg {
                Text("🚆 \(destinationName)")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(legKindLabel) \(NSDateParser.timeString(leg.displayedDeparture))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                StatusLine(status: leg.status, font: .subheadline.weight(.semibold))
            } else if entry.config == nil {
                Text("Set up your journey in the Dutch Commute app")
                    .font(.caption)
            } else {
                Text("No train right now")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    /// Square 1x1 Lock Screen widget: train + status.
    private var circular: some View {
        VStack(spacing: 2) {
            Text("🚆")
                .font(.title2)
            if let leg = entry.leg {
                Text(leg.status.label)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Text("—")
                    .font(.caption2)
            }
        }
    }

    private var inline: some View {
        if let leg = entry.leg {
            Text("🚆 \(destinationName) · \(legKindLabel) \(NSDateParser.timeString(leg.displayedDeparture)) · \(leg.status.label)")
        } else {
            Text("🚆 Dutch Commute")
        }
    }

    private var destinationName: String {
        guard let config = entry.config, let legKind = entry.legKind else { return "" }
        return legKind == .outbound ? config.to.name : config.from.name
    }

    private var legKindLabel: String {
        entry.legKind == .outbound ? String(localized: "Outbound") : String(localized: "Return")
    }
}

private struct StatusLine: View {
    let status: TrainStatus
    var font: Font = .caption

    var body: some View {
        Text(status.label)
            .font(font)
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .onTime: .green
        case .delayed: .orange
        case .cancelled: .red
        case .unknown: .secondary
        }
    }
}

struct JourneyWidget: Widget {
    let kind = "JourneyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JourneyTimelineProvider()) { entry in
            JourneyWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("My journey")
        .description("Your next train and whether it's on time.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .systemExtraLarge,
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline,
        ])
    }
}
