import SwiftUI

/// User-selectable appearance. Defaults to the system setting; persisted in
/// `AppStorage` ("appearance") so it survives launches.
enum Appearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// The `ColorScheme` to apply; nil means "follow the system".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var label: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    /// What is actually shown, resolving `.system` against the environment.
    static func effective(_ preference: Appearance, colorScheme: ColorScheme) -> Appearance {
        preference == .system ? (colorScheme == .dark ? .dark : .light) : preference
    }
}
