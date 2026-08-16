import SwiftUI

/// Settings page: general preferences (appearance). Reached from the gear
/// icon on My journeys.
struct SettingsView: View {
    /// Shared with the widget extension so the Live Activity can follow
    /// the app's theme.
    @AppStorage("appearance", store: UserDefaults(suiteName: AppGroup.identifier) ?? .standard)
    private var appearance = Appearance.system.rawValue

    var body: some View {
        List {
            Section("General") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(Palette.background)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AppState())
    }
}
