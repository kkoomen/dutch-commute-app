import SwiftUI

/// Full-screen launch view: brand gradient (dark teal → cyan, bottom to top)
/// with the app logo centered.
struct LoadingView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.splashDark, Palette.splashLight],
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea()

            Image("LoadingLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
        }
    }
}

#Preview {
    LoadingView()
}
