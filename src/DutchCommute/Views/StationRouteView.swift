import SwiftUI

/// Vertical route diagram: a dot per station with a connecting line that
/// spans from each dot to the next (it grows when rows get taller, e.g.
/// when track captions appear). Optional captions (tracks) sit under each
/// station name.
struct StationRouteView: View {
    /// Ordered station names, e.g. ["Utrecht", "Amsterdam"].
    let stations: [String]
    /// Optional caption per station (e.g. "Spoor 6"); missing entries
    /// render nothing.
    var captions: [String?] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stations.enumerated()), id: \.offset) { index, name in
                HStack(alignment: .top, spacing: 9) {
                    // Dot column: dot on top, flexible line below it so the
                    // line always reaches the next dot, however tall the row.
                    VStack(spacing: 0) {
                        Circle()
                            .fill(Palette.primary)
                            .frame(width: 9, height: 9)
                            .padding(.top, 3)
                        if index < stations.count - 1 {
                            Rectangle()
                                .fill(Palette.primary.opacity(0.35))
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    // Text column: station name, optional caption, and a
                    // spacer that keeps consecutive stations apart.
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                        if let caption = caption(at: index) {
                            Text(caption)
                                .font(.caption2)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        if index < stations.count - 1 {
                            Spacer(minLength: 10)
                        }
                    }
                }
            }
        }
    }

    private func caption(at index: Int) -> String? {
        captions.indices.contains(index) ? captions[index] : nil
    }
}
