import SwiftUI

@main
struct DutchCommuteApp: App {
    @State private var state = AppState()
    @State private var showLoading = true
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showLoading {
                    LoadingView()
                        .transition(.opacity)
                } else {
                    RootView()
                        .environment(state)
                        .transition(.opacity)
                }
            }
            .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
            .task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeOut(duration: 0.4)) {
                    showLoading = false
                }
            }
        }
    }
}
