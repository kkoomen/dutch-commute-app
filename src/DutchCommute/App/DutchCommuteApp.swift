import SwiftUI

@main
struct DutchCommuteApp: App {
    @State private var state = AppState()
    @State private var showLoading = true

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
            .preferredColorScheme(.light)
            .task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeOut(duration: 0.4)) {
                    showLoading = false
                }
            }
        }
    }
}
