import SwiftUI

/// Brand palette — see docs/design.md.
///
/// All roles adapt to the current color scheme (light / dark) and follow
/// the user's appearance setting (system / light / dark).
enum Palette {
    // Surfaces
    /// Page background behind cards and forms.
    static let background = adaptive(light: 0xF8FAFC, dark: 0x0E0F11)
    /// Cards, list rows, sheets.
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1D2324)
    /// Secondary fills: unselected day toggles, mode tiles.
    static let surfaceSecondary = adaptive(light: 0xD6DBD9, dark: 0x202F2F)

    // Text
    static let textPrimary = adaptive(light: 0x0C0D0F, dark: 0xE1DFDB)
    static let textSecondary = adaptive(light: 0x606569, dark: 0x8D9193)
    static let textTertiary = adaptive(light: 0xACB0B0, dark: 0x525D5E)

    // Accent
    /// Buttons, selected states, links, checkmarks.
    static let primary = adaptive(light: 0x007572, dark: 0x5ABAB1)
    /// Primary buttons while pressed.
    static let primaryPressed = adaptive(light: 0x00605E, dark: 0x4AA29B)
    /// Text on accent fills.
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x0E0F11)

    // Semantic status
    static let statusOnTime = adaptive(light: 0x5AA58B, dark: 0x6CB87A)

    // Launch screen (brand splash, always the teal gradient)
    static let splashDark = Color(hex: 0x083B4C)
    static let splashLight = Color(hex: 0x4CC9C0)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    /// RGB hex, e.g. `UIColor(hex: 0x007572)`.
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    /// RGB hex, e.g. `Color(hex: 0x083B4C)`.
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}
