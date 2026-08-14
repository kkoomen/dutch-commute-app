import SwiftUI

/// Filled brand button: primary background with black text, darker while
/// pressed, gray (fill + text) when disabled.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.black : Palette.disabledText)
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
