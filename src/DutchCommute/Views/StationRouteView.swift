import SwiftUI

/// Vertical route diagram: a dot per station with connecting lines,
/// e.g. from → (via) → to. Optional captions (tracks) sit under each
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
                    Circle()
                        .fill(Palette.primary)
                        .frame(width: 9, height: 9)
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                        if let caption = caption(at: index) {
                            Text(caption)
                                .font(.caption2)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
                if index < stations.count - 1 {
                    Rectangle()
                        .fill(Palette.primary.opacity(0.35))
                        .frame(width: 2, height: 20)
                        .padding(.leading, 3.5)
                }
            }
        }
    }

    private func caption(at index: Int) -> String? {
        captions.indices.contains(index) ? captions[index] : nil
    }
}
