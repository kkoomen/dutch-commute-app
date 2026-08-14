import SwiftUI

/// Filled brand button: accent fill with contrasting label (white on the
/// dark teal accent in light mode, near-black on the light teal accent in
/// dark mode), darker while pressed, gray (fill + text) when disabled.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? Palette.onAccent : Palette.disabledText)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(fillColor(isPressed: configuration.isPressed))
            )
    }

    private func fillColor(isPressed: Bool) -> Color {
        guard isEnabled else { return Palette.disabledFill }
        return isPressed ? Palette.primaryPressed : Palette.primary
    }
}
