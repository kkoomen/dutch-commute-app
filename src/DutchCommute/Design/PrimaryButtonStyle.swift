import SwiftUI

/// Filled brand button: primary background, white text, darker while pressed,
/// dimmed when disabled.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Palette.white)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(configuration.isPressed ? Palette.primaryPressed : Palette.primary)
            )
            .opacity(isEnabled ? 1 : 0.4)
    }
}
