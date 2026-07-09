import SwiftUI

/// The launch/loading screen shown by `RootView` while auth resolves (`.loading`).
///
/// Deliberately echoes `AuthView`'s header — same icon, wordmark, and warm
/// gradient — so that when a cold launch restores a session, the hand-off to the
/// app (or, for a genuinely signed-out user, to the login screen) reads as one
/// continuous surface rather than a flash between two unrelated screens. This is
/// the screen the app now *holds* on during a token refresh, instead of briefly
/// dropping to the login screen — see `AuthViewModel.apply(_:)`.
struct SplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.18), Color.platformBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 64))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)

                Text("VJ Test Kitchen")
                    .font(.largeTitle.bold())

                ProgressView()
                    .padding(.top, 8)
            }
        }
    }
}

#Preview {
    SplashView()
}
