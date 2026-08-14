import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let config = state.config, !state.isEditing {
            JourneyView(config: config)
        } else {
            SetupView(prefill: state.config)
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
}
