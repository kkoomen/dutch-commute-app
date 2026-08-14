import SwiftUI

@main
struct DutchCommuteWidgetApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
        }
    }
}
