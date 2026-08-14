import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationStack(path: $state.path) {
            JourneyListView()
                .navigationDestination(for: JourneyRoute.self) { route in
                    switch route {
                    case .journey(let id):
                        if let journey = state.journeys.first(where: { $0.id == id }) {
                            JourneyView(config: journey)
                        }
                    case .setup(let id):
                        SetupView(prefill: id.flatMap { id in
                            state.journeys.first(where: { $0.id == id })
                        })
                    }
                }
        }
        .tint(Palette.primary)
        .preferredColorScheme(.light)
        .background(Palette.lightBackground)
    }
}

#Preview {
    RootView()
        .environment(AppState())
}
