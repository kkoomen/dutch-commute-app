import SwiftUI

/// Brand palette — see docs/design.md.
enum Palette {
    /// Dark teal chrome: navigation bars, widget backgrounds.
    static let darkBackground = Color(hex: 0x083B4C)
    /// Cyan page background behind cards and forms.
    static let lightBackground = Color(hex: 0x4CC9C0)
    /// Accent for buttons, selected states, links, checkmarks.
    static let primary = Color(hex: 0x19B8B0)
    /// Primary buttons while pressed.
    static let primaryPressed = Color(hex: 0x12938D)
    /// Text and icons on dark surfaces.
    static let white = Color(hex: 0xF4FFFF)
    /// Text on light surfaces.
    static let darkText = Color(hex: 0x06343F)
}

extension Color {
    /// RGB hex, e.g. `Color(hex: 0x19B8B0)`.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension View {
    /// Brand navigation bar: dark teal bar with white titles and buttons.
    func brandedNavigationBar() -> some View {
        self
            .toolbarBackground(Palette.darkBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
