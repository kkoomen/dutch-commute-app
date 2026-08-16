import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity UI: route, stations, departure time, status, and stale
/// state. Rendered by the system from this configuration.
struct JourneyLiveActivityView: View {
    let context: ActivityViewContext<JourneyActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("🚆 \(context.state.routeName)")
                    .font(.headline)
                Spacer()
                if context.state.isStale {
                    Label(String(localized: "Unavailable"), systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 4) {
                Text(context.attributes.fromName)
                Text("→")
                Text(context.attributes.destination)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            HStack {
                Text(context.state.departureTime, style: .time)
                    .font(.title3.monospacedDigit())
                    .strikethrough(context.state.isCancelled)
                Spacer()
                Text(context.state.status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(context.state.isCancelled ? .red : .primary)
            }
        }
        .padding()
        .activityBackgroundTint(.secondary)
        .activitySystemActionForegroundColor(.primary)
    }
}

/// The Live Activity for a journey. Registered in the widget bundle.
struct JourneyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JourneyActivityAttributes.self) { context in
            JourneyLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("🚆 \(context.state.routeName)")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.departureTime, style: .time)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.status)
                        Spacer()
                        if context.state.isStale {
                            Label(String(localized: "Unavailable"), systemImage: "exclamationmark.triangle")
                        }
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Text("🚆")
            } compactTrailing: {
                Text(context.state.departureTime, style: .time)
                    .monospacedDigit()
            } minimal: {
                Text("🚆")
            }
        }
    }
}
