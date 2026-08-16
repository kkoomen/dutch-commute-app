import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity UI: route title, train + track, departure time and
/// status. Rendered by the system from this configuration.
///
/// Follows the app's appearance setting (System / Light / Dark), shared
/// through the App Group. Colors are resolved explicitly per scheme:
/// ActivityKit resolves dynamic colors passed to `activityBackgroundTint`
/// against the wrong (light) appearance on dark devices, so adaptive
/// colors like `Palette.surface` must not be used here. The device scheme
/// is read from SwiftUI's `colorScheme` environment — global trait
/// collections (`UITraitCollection.current`) are not updated reliably in
/// the Live Activity render context and report light on dark devices.
struct JourneyLiveActivityView: View {
    let context: ActivityViewContext<JourneyActivityAttributes>

    @Environment(\.colorScheme) private var systemScheme

    @AppStorage("appearance", store: UserDefaults(suiteName: AppGroup.identifier) ?? .standard)
    private var appearanceRaw = Appearance.system.rawValue

    /// The scheme to render: the app's explicit choice, or the device's
    /// current scheme when set to System.
    private var scheme: ColorScheme {
        switch Appearance(rawValue: appearanceRaw) ?? .system {
        case .light: .light
        case .dark: .dark
        case .system: systemScheme
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                // Same train glyph as the station picker (`TransportMode.train`).
                Image(systemName: TransportMode.train.icon)
                    .font(.headline)
                Text("\(context.state.fromName) → \(context.state.toName)")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                if context.state.isStale {
                    Label(String(localized: "Unavailable"), systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 5) {
                Text(context.state.routeName)
                if let track = context.state.track {
                    Text("·")
                    Text(String(localized: "Track \(track)"))
                }
            }
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary(for: scheme))
            HStack {
                Text(context.state.departureTime, style: .time)
                    .font(.title3.monospacedDigit())
                    .strikethrough(context.state.isCancelled)
                Spacer()
                Text(context.state.status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(context.state.isCancelled ? .red : Palette.textPrimary(for: scheme))
            }
        }
        .padding()
        .foregroundStyle(Palette.textPrimary(for: scheme))
        .activityBackgroundTint(Palette.surface(for: scheme))
        .activitySystemActionForegroundColor(Palette.textPrimary(for: scheme))
    }
}

/// Semantic status color for the Dynamic Island: the island is always
/// black, so fixed colors work regardless of the device scheme.
/// Unknown/missing kind renders neutral (white).
private func statusColor(for kind: StatusKind?) -> Color {
    switch kind ?? .unknown {
    case .onTime: .green
    case .delayed: .orange
    case .cancelled: .red
    case .unknown: .white
    }
}

/// The Live Activity for a journey. Registered in the widget bundle.
struct JourneyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JourneyActivityAttributes.self) { context in
            JourneyLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Image(systemName: TransportMode.train.icon)
                                            .font(.subheadline)
                                        HStack(spacing: 3) {
                                            Text(context.state.routeName)
                                            if let track = context.state.track {
                                                Text("· \(String(localized: "Track \(track)"))")
                                            }
                                        }
                                        .font(.caption)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    }
                                    Text(context.state.toName)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                        .allowsTightening(true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(context.state.departureTime, style: .time)
                                        .font(.title3.monospacedDigit())
                                    Text(context.state.status)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(statusColor(for: context.state.statusKind))
                                }
                        }

                        if context.state.isStale {
                            Label(String(localized: "Unavailable"), systemImage: "exclamationmark.triangle")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 16)
                }
            } compactLeading: {
                Image(systemName: TransportMode.train.icon)
                    .font(.caption)
            } compactTrailing: {
                Text(context.state.departureTime, style: .time)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: TransportMode.train.icon)
                    .font(.caption)
            }
        }
    }
}
