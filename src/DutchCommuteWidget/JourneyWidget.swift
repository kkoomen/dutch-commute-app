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
    /// active journey (or the first one when none is marked active).
    private func makeEntry() async -> JourneyEntry {
        let now = Date()
        let journeys = ConfigStore().load()
        guard let config = journeys.first(where: \.isActive) ?? journeys.first else {
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
    }

    /// Wide 2x1 Lock Screen widget: destination, leg, then time + status on
    /// the last line.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let leg = entry.leg {
                Text(destinationName)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 4) {
                    Text(legKindLabel)
                    if let track = leg.departureTrack {
                        Text("·")
                        Text(String(localized: "Track \(track)"))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .font(.caption)
                Text("\(NSDateParser.timeString(leg.displayedDeparture)) · \(widgetStatusText(leg.status))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            } else if entry.config == nil {
                Text("Set up your journey in the Dutch Commute app")
                    .font(.caption)
            } else {
                Text("No train right now")
                    .font(.caption)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
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
                    .foregroundStyle(Palette.textPrimary)
                Text("\(legKindLabel) \(NSDateParser.timeString(leg.displayedDeparture))")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                StatusLine(status: leg.status, font: .subheadline.weight(.semibold))
            } else if entry.config == nil {
                Text("Set up your journey in the Dutch Commute app")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                Text("No train right now")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .containerBackground(Palette.background, for: .widget)
    }

    /// Square 1x1 Lock Screen widget: leg, time, status.
    private var circular: some View {
        VStack(spacing: 2) {
            Text(legKindLabel)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let leg = entry.leg {
                Text(NSDateParser.timeString(leg.displayedDeparture))
                    .font(.caption2)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(widgetStatusText(leg.status))
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Text("—")
                    .font(.caption2)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var inline: some View {
        if let leg = entry.leg {
            Text("🚆 \(destinationName) · \(legKindLabel) \(NSDateParser.timeString(leg.displayedDeparture)) · \(widgetStatusText(leg.status))")
        } else {
            Text("🚆 Dutch Commute")
        }
    }

    private var destinationName: String {
        guard let config = entry.config, let legKind = entry.legKind else { return "" }
        return legKind == .outbound ? config.to.name : config.from.name
    }

    private var legKindLabel: String {
        guard let legKind = entry.legKind else { return "—" }
        return legKind == .outbound ? String(localized: "Outbound") : String(localized: "Return")
    }
}

/// Status label with an emoji: ⚠️ when delayed, ❗ when cancelled.
/// (Lock Screen accessory widgets cannot show custom colors, so status is
/// conveyed with emoji instead.)
fileprivate func widgetStatusText(_ status: TrainStatus) -> String {
    switch status {
    case .onTime: status.label
    case .delayed: "⚠️ \(status.label)"
    case .cancelled: "❗ \(status.label)"
    case .unknown: status.label
    }
}

private struct StatusLine: View {
    let status: TrainStatus
    var font: Font = .caption

    var body: some View {
        Text(widgetStatusText(status))
            .font(font)
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
